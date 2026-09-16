require 'spec_helper'
require 'ostruct'
require 'omniauth-azure-activedirectory'

def build_strategy(session: {}, **options)
  OpenStruct.new(
    session: session,
    options: OpenStruct.new({ nonce_max_count: 10, nonce_ttl: 900 }.merge(options))
  )
end

describe OmniAuth::AzureActiveDirectory::SessionNonceStore do
  let(:session) { {} }
  let(:strategy) { build_strategy(session: session, nonce_max_count: 2) }
  subject { described_class.new(strategy) }

  it 'keeps the session shape used by earlier releases' do
    subject.store('n1')
    expect(session).to eq('omniauth-azure-activedirectory.nonces' => ['n1'])
  end

  it 'drops the oldest nonce beyond nonce_max_count' do
    %w(n1 n2 n3).each { |n| subject.store(n) }
    expect(session['omniauth-azure-activedirectory.nonces']).to eq %w(n2 n3)
  end

  it 'does not claim the same nonce twice in sequence' do
    subject.store('n1')
    expect(subject.claim('n1')).to be_truthy
    expect(subject.claim('n1')).to be_falsey
  end

  it 'claims nonces other than the most recent, so several tabs can log in' do
    subject.store('n1')
    subject.store('n2')
    expect(subject.claim('n1')).to be_truthy
  end

  it 'is falsey for an unknown nonce and for an untouched session' do
    expect(subject.claim('nope')).to be_falsey
    subject.store('n1')
    expect(subject.claim('nope')).to be_falsey
  end
end

describe OmniAuth::AzureActiveDirectory::CacheNonceStore do
  let(:cache) { FakeCache.new }
  let(:strategy) { build_strategy(nonce_cache: cache, nonce_ttl: 120) }
  subject { described_class.new(strategy) }

  it 'writes under a namespaced key with the configured ttl' do
    subject.store('n1')
    key, _value, opts = cache.writes.first
    expect(key).to eq 'omniauth-azure-activedirectory:nonce:n1'
    expect(opts[:expires_in]).to eq 120
  end

  it 'does not claim the same nonce twice in sequence' do
    subject.store('n1')
    expect(subject.claim('n1')).to be_truthy
    expect(subject.claim('n1')).to be_falsey
  end

  it 'removes the nonce from the cache when claimed' do
    subject.store('n1')
    subject.claim('n1')
    expect(cache.key?('omniauth-azure-activedirectory:nonce:n1')).to be false
  end

  it 'is falsey for an unknown, nil or empty nonce' do
    expect(subject.claim('nope')).to be_falsey
    expect(subject.claim(nil)).to be_falsey
    expect(subject.claim('')).to be_falsey
  end

  it 'does not touch the session' do
    subject.store('n1')
    expect(strategy.session).to eq({})
  end

  # payload/on_claim are the documented extension point, so the contract they
  # rely on is worth pinning: each nonce carries its own snapshot, captured when
  # it was stored, and claim hands back exactly that.
  context 'payload isolation' do
    let(:store_class) do
      Class.new(described_class) do
        attr_accessor :source
        attr_reader :received

        def payload
          { 'return_to' => source }
        end

        def on_claim(payload)
          @received = payload['return_to']
        end
      end
    end

    subject { store_class.new(strategy) }

    it 'keeps sequential logins independent' do
      subject.source = '/link/one'
      subject.store('n1')
      subject.claim('n1')
      expect(subject.received).to eq '/link/one'

      subject.source = '/link/two'
      subject.store('n2')
      subject.claim('n2')
      expect(subject.received).to eq '/link/two'
    end

    # Two tabs, claimed out of the order they were issued.
    it 'keeps concurrent nonces from crossing payloads' do
      subject.source = '/tab/alpha'
      subject.store('alpha')
      subject.source = '/tab/beta'
      subject.store('beta')

      subject.claim('beta')
      expect(subject.received).to eq '/tab/beta'
      subject.claim('alpha')
      expect(subject.received).to eq '/tab/alpha'
    end

    # The snapshot is taken at store time, not read at claim time. This is what
    # makes the two cases above hold.
    it 'captures the payload when the nonce is stored, not when it is claimed' do
      subject.source = '/at/store/time'
      subject.store('n1')
      subject.source = '/changed/afterwards'
      subject.claim('n1')
      expect(subject.received).to eq '/at/store/time'
    end

    # A nonce stored before the value existed hands back nil. Whether that then
    # clobbers a value set in the meantime is the implementor's call, which is
    # why the README example guards the assignment - see the next example.
    it 'hands back what was stored even when that is nil' do
      subject.source = nil
      subject.store('n1')
      subject.claim('n1')
      expect(subject.received).to be_nil
    end

    it 'lets a guarded on_claim preserve a value set after the nonce was stored' do
      guarded = Class.new(described_class) do
        def payload
          { 'return_to' => session['user_return_to'] }
        end

        def on_claim(payload)
          session['user_return_to'] = payload['return_to'] if payload['return_to']
        end
      end.new(strategy)

      guarded.store('n1')                              # session empty at store time
      strategy.session['user_return_to'] = '/set/later'
      guarded.claim('n1')

      expect(strategy.session['user_return_to']).to eq '/set/later'
    end
  end

  context 'when the cache write fails' do
    let(:cache) { FakeCache.new(write_result: false) }

    # A silently dropped nonce would surface at the callback as 'nonce did not
    # match', sending anyone debugging it towards the JWT rather than the cache.
    it 'raises rather than letting the login fail later as a nonce mismatch' do
      expect { subject.store('n1') }
        .to raise_error(OmniAuth::Error, /could not store/i)
    end
  end

  # The store must produce one error whether the backend returns falsey or
  # raises. Which one you get depends on the host app's cache: a Redis OOM
  # raises through redis-activesupport (it rescues only BaseConnectionError)
  # but is swallowed by Rails' RedisCacheStore.
  context 'when the cache raises instead of returning' do
    let(:cache) { FakeCache.new(raise_on: :write) }

    it 'still raises OmniAuth::Error, not the backend error' do
      expect { subject.store('n1') }
        .to raise_error(OmniAuth::Error, /could not store/i)
    end

    it 'keeps the original error as the cause' do
      begin
        subject.store('n1')
      rescue OmniAuth::Error => e
        expect(e.cause).to be_a RuntimeError
        expect(e.message).to match(/OOM/)
      end
    end
  end

  context 'when the cache raises on read' do
    let(:cache) { FakeCache.new(raise_on: :read) }

    # Distinct from a miss: the nonce may have been perfectly valid.
    it 'raises rather than reporting a nonce mismatch' do
      expect { subject.claim('n1') }
        .to raise_error(OmniAuth::Error, /could not read/i)
    end
  end

  context 'when the cache raises on delete' do
    let(:cache) { FakeCache.new(raise_on: :delete) }

    # The nonce was found; refusing a valid login over a failed cleanup would
    # be worse than the widened replay window.
    it 'still claims the nonce' do
      cache.instance_variable_set(:@raise_on, [])
      subject.store('n1')
      cache.instance_variable_set(:@raise_on, [:delete])
      expect(subject.claim('n1')).to be true
    end
  end

  context 'with a logger' do
    let(:logged) { [] }
    let(:logger) do
      Class.new do
        def initialize(sink); @sink = sink; end
        def warn(msg); @sink << [:warn, msg]; end
        def error(msg); @sink << [:error, msg]; end
      end.new(logged)
    end
    let(:strategy) { build_strategy(nonce_cache: cache, nonce_logger: logger) }

    it 'distinguishes a missing nonce from an absent one' do
      subject.claim('never-issued')
      subject.claim(nil)
      expect(logged.map(&:first)).to eq %i(warn warn)
      expect(logged[0][1]).to match(/expired, already used, or evicted/)
      expect(logged[1][1]).to match(/carried no nonce/)
    end

    it 'logs write failures at error level' do
      allow(cache).to receive(:write).and_return(false)
      expect { subject.store('n1') }.to raise_error(OmniAuth::Error)
      expect(logged.first.first).to eq :error
    end

    it 'never lets a broken logger break a login' do
      allow(logger).to receive(:warn).and_raise('logger exploded')
      expect(subject.claim('never-issued')).to be false
    end
  end

  # A bug in a subclass's #payload is not a cache failure.
  context 'when the subclass payload raises' do
    subject do
      Class.new(described_class) do
        def payload
          fail ArgumentError, 'bug in payload'
        end
      end.new(strategy)
    end

    it 'lets the original error through rather than blaming the cache' do
      expect { subject.store('n1') }.to raise_error(ArgumentError, /bug in payload/)
    end
  end

  context 'when no cache is configured' do
    let(:strategy) { build_strategy(nonce_cache: nil) }

    it 'raises a configuration error naming the missing option' do
      expect { subject.store('n1') }
        .to raise_error(OmniAuth::Error, /nonce_cache/)
    end
  end

  context 'with a subclass carrying a payload' do
    let(:store_class) do
      Class.new(described_class) do
        attr_reader :claimed

        def payload
          { 'return_to' => '/deep/link' }
        end

        def on_claim(payload)
          @claimed = payload['return_to']
        end
      end
    end

    subject { store_class.new(strategy) }

    it 'round-trips the payload through the cache' do
      subject.store('n1')
      expect(subject.claim('n1')).to be_truthy
      expect(subject.claimed).to eq '/deep/link'
    end
  end
end
