#-------------------------------------------------------------------------------
# Copyright (c) 2015 Micorosft Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

require 'omniauth/azure_activedirectory/nonce_store'

module OmniAuth
  module AzureActiveDirectory
    ##
    # Keeps nonces in a shared cache instead of the session, so they survive the
    # cross-site form_post callback under SameSite=Lax and are visible to every
    # application server without sticky sessions.
    #
    # Requires :nonce_cache, any object responding to #read, #write (accepting
    # an :expires_in keyword) and #delete -- Rails.cache satisfies this. The
    # gem does not depend on Rails; the cache is injected.
    #
    #   provider :azure_activedirectory, client_id, tenant,
    #            nonce_store: OmniAuth::AzureActiveDirectory::CacheNonceStore,
    #            nonce_cache: Rails.cache,
    #            nonce_ttl: 900
    class CacheNonceStore < NonceStore
      KEY_PREFIX = 'omniauth-azure-activedirectory:nonce:'.freeze

      ##
      # Persists the nonce, converting ANY failure into one OmniAuth::Error.
      #
      # Two distinct failure shapes have to collapse into one: a store may
      # return falsey, or it may raise. Which one you get depends on the host
      # application's cache and how narrowly it rescues -- redis-activesupport
      # rescues only Redis::BaseConnectionError (and re-raises even that when
      # raise_errors? is set), while Rails' RedisCacheStore also swallows
      # Redis::BaseError. So a Redis OOM raises straight through the first and
      # is caught by the second.
      #
      # Without this, an OOM on one app surfaces as a bare Redis::CommandError
      # that no `rescue_from OmniAuth::Error` will catch, and on the other as a
      # clear message. The guarantee worth offering is that a nonce which was
      # not stored always produces the same error, whatever the host configured.
      def store(nonce)
        # Computed outside the rescue: a bug in a subclass's #payload is not a
        # cache failure and should not be reported as one.
        data = payload
        backend = cache

        written =
          begin
            backend.write(cache_key(nonce), data, expires_in: ttl)
          rescue StandardError => e
            log(:error, "cache write raised #{e.class}: #{e.message}")
            fail ::OmniAuth::Error, write_failure_message(backend, e)
          end

        # `unless written` rather than `written == false`: the truthy value is
        # store-specific. redis-activesupport returns "OK" where Rails'
        # RedisCacheStore returns true, and an equality check against either
        # would stop firing if the store were swapped.
        unless written
          log(:error, "cache write returned #{written.inspect}")
          fail ::OmniAuth::Error, write_failure_message(backend)
        end

        nonce
      end

      def claim(nonce)
        if nonce.nil? || nonce.to_s.empty?
          log(:warn, 'callback carried no nonce')
          return false
        end

        backend = cache

        stored =
          begin
            backend.read(cache_key(nonce))
          rescue StandardError => e
            # Distinct from a miss: the nonce may well have been valid. Saying
            # so beats letting this surface as 'nonce did not match'.
            log(:error, "cache read raised #{e.class}: #{e.message}")
            fail ::OmniAuth::Error,
                 'Could not read the Azure AD login nonce from the cache ' \
                 "(#{backend.class}): #{e.class}: #{e.message}"
          end

        if stored.nil?
          log(:warn, "nonce not claimable: expired, already used, or evicted (#{cache_key(nonce)})")
          return false
        end

        begin
          backend.delete(cache_key(nonce))
        rescue StandardError => e
          # Deliberately not fatal. The realistic trigger is failover to a
          # read-only replica, where reads succeed and writes and deletes fail:
          # failing closed there is a total login outage for the duration of the
          # failover, while failing open widens the replay window to the TTL and
          # still requires an attacker to hold a valid signed id_token. Certain
          # and total availability loss versus conditional and bounded exposure.
          # Note an OOM does not reach here -- Redis permits DEL under maxmemory
          # because it frees memory.
          log(:error, "cache delete raised #{e.class}: #{e.message}; nonce stays until it expires")
        end

        on_claim(stored)
        true
      end

      private

      def cache
        options.nonce_cache ||
          fail(::OmniAuth::Error,
               'nonce_store is CacheNonceStore but no :nonce_cache was ' \
               'configured. Pass one, e.g. nonce_cache: Rails.cache.')
      end

      def ttl
        options.nonce_ttl
      end

      def cache_key(nonce)
        "#{KEY_PREFIX}#{nonce}"
      end

      def write_failure_message(backend, error = nil)
        detail = error ? "#{error.class}: #{error.message}" : 'the write was rejected'
        'Could not store the Azure AD login nonce. Azure AD sign-in cannot ' \
          "work until the cache (#{backend.class}) accepts writes -- #{detail}."
      end
    end
  end
end
