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

module OmniAuth
  module AzureActiveDirectory
    ##
    # Base class for nonce stores.
    #
    # The strategy generates a nonce for each request phase and must find it
    # again at the callback. Where that nonce lives is pluggable, because the
    # default (the Rack session) is unreachable in some deployments: Azure
    # returns the id_token via a cross-site form_post, and a SameSite=Lax
    # session cookie is not sent on a cross-site POST.
    #
    # Configure with the :nonce_store option, which takes a class instantiated
    # with the strategy, mirroring :tenant_provider:
    #
    #   provider :azure_activedirectory, client_id, tenant,
    #            nonce_store: OmniAuth::AzureActiveDirectory::CacheNonceStore,
    #            nonce_cache: Rails.cache
    #
    # Subclasses implement #store and #claim, and may override #payload and
    # #on_claim to carry data of their own across the round trip.
    class NonceStore
      attr_reader :strategy

      def initialize(strategy)
        @strategy = strategy
      end

      ##
      # Persist a nonce. Must raise if persistence fails: a nonce that was not
      # stored cannot be claimed, so every login through this strategy would
      # fail at the callback with a misleading 'nonce did not match'.
      #
      # @param String nonce
      def store(_nonce)
        fail NotImplementedError, "#{self.class}#store"
      end

      ##
      # Claim a nonce. Nonces are one-time use: a successful claim must remove
      # it so it cannot be claimed again.
      #
      # @param String nonce
      # @return truthy if the nonce was outstanding, falsey otherwise
      def claim(_nonce)
        fail NotImplementedError, "#{self.class}#claim"
      end

      ##
      # Extra data to persist alongside the nonce. Override to carry state
      # across the callback that the session cannot hold.
      #
      # @return Hash
      def payload
        {}
      end

      ##
      # Called with the persisted payload when a nonce is successfully claimed.
      # Override alongside #payload.
      def on_claim(payload); end

      private

      def options
        strategy.options
      end

      def session
        strategy.session
      end
    end
  end
end
