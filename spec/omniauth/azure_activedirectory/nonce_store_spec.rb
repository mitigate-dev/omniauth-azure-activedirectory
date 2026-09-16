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

  it 'claims an outstanding nonce exactly once' do
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

  it 'claims an outstanding nonce exactly once' do
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

  context 'when the cache write fails' do
    let(:cache) { FakeCache.new(write_result: false) }

    # A silently dropped nonce would surface at the callback as 'nonce did not
    # match', sending anyone debugging it towards the JWT rather than the cache.
    it 'raises rather than letting the login fail later as a nonce mismatch' do
      expect { subject.store('n1') }
        .to raise_error(OmniAuth::Error, /cache.*reachable/i)
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
