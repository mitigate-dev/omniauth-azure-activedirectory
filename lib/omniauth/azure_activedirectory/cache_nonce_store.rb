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

      def store(nonce)
        written = cache.write(cache_key(nonce), payload, expires_in: ttl)

        # Deliberately `unless written` rather than `written == false`: the
        # truthy value is store-specific. redis-rails' :redis_store returns
        # "OK" where Rails' own :redis_cache_store returns true, and an
        # equality check against either would stop firing if the store is
        # swapped. Neither raises on a dead backend, so this is the only
        # signal available.
        unless written
          fail ::OmniAuth::Error,
               'Could not store the Azure AD login nonce. Azure AD sign-in ' \
               "cannot work until the cache (#{cache.class}) is reachable."
        end

        nonce
      end

      def claim(nonce)
        return false if nonce.nil? || nonce.to_s.empty?

        stored = cache.read(cache_key(nonce))
        return false if stored.nil?

        cache.delete(cache_key(nonce))
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
    end
  end
end
