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
    # Keeps nonces in the Rack session. This is the default and reproduces the
    # behaviour the strategy has had since 1.2.0, including the session key and
    # the :nonce_max_count cap.
    #
    # Note that this store does not work when the session cookie is
    # SameSite=Lax (or stricter), because Azure returns the id_token via a
    # cross-site POST and the cookie is not sent with it. Use CacheNonceStore
    # in that case.
    #
    # Payloads are not supported: the session holds bare nonce strings so the
    # stored shape stays compatible with earlier releases.
    class SessionNonceStore < NonceStore
      SESSION_KEY = 'omniauth-azure-activedirectory.nonces'.freeze

      ##
      # Appends the nonce, dropping the oldest once :nonce_max_count is
      # exceeded. The cap is what allows several tabs to authenticate
      # concurrently without invalidating each other.
      def store(nonce)
        session[SESSION_KEY] ||= []
        session[SESSION_KEY] << nonce
        if session[SESSION_KEY].size > options.nonce_max_count
          session[SESSION_KEY].shift
        end
        nonce
      end

      def claim(nonce)
        return false unless session[SESSION_KEY]
        return false unless session[SESSION_KEY].delete(nonce)
        on_claim(payload)
        true
      end
    end
  end
end
