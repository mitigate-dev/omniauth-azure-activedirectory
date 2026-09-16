# OmniAuth Azure Active Directory
[![Build Status](https://travis-ci.org/AzureAD/omniauth-azure-activedirectory.png?branch=master)](https://travis-ci.org/AzureAD/omniauth-azure-activedirectory)
[![Code Climate](https://codeclimate.com/github/AzureAD/omniauth-azure-activedirectory/badges/gpa.svg)](https://codeclimate.com/github/AzureAD/omniauth-azure-activedirectory/badges/gpa.svg)

OmniAuth strategy to authenticate to Azure Active Directory via OpenId Connect.

Before starting, set up a tenant and register a Web Application at [https://manage.windowsazure.com](https://manage.windowsazure.com). Note your client id and tenant for later.

## Samples and Documentation

[We provide a full suite of sample applications and documentation on GitHub](https://github.com/AzureADSamples) to help you get started with learning the Azure Identity system. This includes tutorials for native clients such as Windows, Windows Phone, iOS, OSX, Android, and Linux. We also provide full walkthroughs for authentication flows such as OAuth2, OpenID Connect, Graph API, and other awesome features. 

## Community Help and Support

We leverage [Stack Overflow](http://stackoverflow.com/) to work with the community on supporting Azure Active Directory and its SDKs, including this one! We highly recommend you ask your questions on Stack Overflow (we're all on there!) Also browser existing issues to see if someone has had your question before. 

We recommend you use the "adal" tag so we can see it! Here is the latest Q&A on Stack Overflow for ADAL: [http://stackoverflow.com/questions/tagged/adal](http://stackoverflow.com/questions/tagged/adal)

## Security Reporting

If you find a security issue with our libraries or services please report it to [secure@microsoft.com](mailto:secure@microsoft.com) with as much detail as possible. Your submission may be eligible for a bounty through the [Microsoft Bounty](http://aka.ms/bugbounty) program. Please do not post security issues to GitHub Issues or any other public site. We will contact you shortly upon receiving the information. We encourage you to get notifications of when security incidents occur by visiting [this page](https://technet.microsoft.com/en-us/security/dd252948) and subscribing to Security Advisory Alerts.

## We Value and Adhere to the Microsoft Open Source Code of Conduct

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## How to use this SDK

#### Installation

Add to your Gemfile:

```ruby
gem 'omniauth-azure-activedirectory'
```

### Usage

If you are already using OmniAuth, adding AzureAD is as simple as adding a new provider to your `OmniAuth::Builder`. The provider requires your AzureAD client id and your AzureAD tenant.

For example, in Rails you would add this in `config/initializers/omniauth.rb`:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :azure_activedirectory, ENV['AAD_CLIENT_ID'], ENV['AAD_TENANT']
  # other providers here
end
```

If you are using Sinatra or something else that requires you to configure Rack yourself, you should add this to your `config.ru`:

```ruby
use OmniAuth::Builder do
  provider :azure_activedirectory, ENV['AAD_CLIENT_ID'], ENV['AAD_TENANT']
end
```

When you want to authenticate the user, send them to `/auth/azureactivedirectory`. From there, OmniAuth will takeover. Once the user authenticates (or fails to authenticate), they will be redirected to `/auth/azureactivedirectory/callback` or `/auth/azureactivedirectory/failure`. The authentication result is available in `request.env['omniauth.auth']`.

**How you send them there depends on your OmniAuth version.** This gem supports
`omniauth >= 1.1, < 3`, and the two majors differ on the request phase.

### Starting the request phase

On **OmniAuth 1.x**, the request phase accepts GET, so a plain link or redirect works:

```ruby
redirect_to '/auth/azureactivedirectory'
```

On **OmniAuth 2.x**, the request phase accepts **POST only**
(`OmniAuth.config.allowed_request_methods` defaults to `[:post]`). A GET link or
redirect no longer reaches the strategy, so the snippet above silently stops
working. In Rails, add the CSRF protection middleware:

```ruby
# Gemfile
gem 'omniauth-rails_csrf_protection'
```

and start authentication with a POST that carries the CSRF token:

```erb
<%= button_to 'Sign in with Azure AD', '/auth/azureactivedirectory', method: :post %>
```

If your application redirects unauthenticated users to a sign-in path, that path
cannot point straight at the request phase either, since a 302 cannot produce a
POST. Have it render a small interstitial that submits the form itself:

```erb
<%= form_with url: '/auth/azureactivedirectory', method: :post, id: 'aad-signin' do %>
  <noscript><%= submit_tag 'Continue to sign in' %></noscript>
<% end %>
<script>document.getElementById('aad-signin').submit()</script>
```

The sample applications in `examples/` predate OmniAuth 2 and still start
authentication with a GET link, so they run on OmniAuth 1.x only.

#### Do not re-enable GET

The quickest-looking fix is to put the old behaviour back:

```ruby
# Don't do this.
OmniAuth.config.allowed_request_methods = %i[get post]
```

Restricting the request phase to POST is precisely how OmniAuth 2 fixes
[CVE-2015-9284](https://nvd.nist.gov/vuln/detail/CVE-2015-9284), a request-phase
CSRF vulnerability that lets an attacker link a victim's session to an account the
attacker controls. Re-enabling GET silences the symptom and restores the
vulnerability. Use a POST form instead.

If you are supporting multiple OmniAuth providers, you will likely have something like this in your code:

```ruby
%w(get post).each do |method|
  send(method, '/auth/:provider/callback') do
    auth = request.env['omniauth.auth']

    # Do what you see fit with your newly authenticated user.

  end
end
```

### Nonce storage

The strategy generates a nonce during the request phase and must find it again
at the callback. By default it keeps nonces in the Rack session, capped at
`nonce_max_count` (10) so that logins started in several tabs do not invalidate
each other.

**The session default does not work under `SameSite=Lax`.** Azure returns the
`id_token` via `response_mode=form_post`, which is a cross-site POST, and a
`SameSite=Lax` session cookie is not sent with it. The session is therefore
empty at the callback, the nonce cannot be found, and every login fails with
`Returned nonce did not match.`. The same applies across application servers
without sticky sessions.

Keep nonces in a shared cache instead:

```ruby
provider :azure_activedirectory, ENV['AAD_CLIENT_ID'], ENV['AAD_TENANT'],
         nonce_store: OmniAuth::AzureActiveDirectory::CacheNonceStore,
         nonce_cache: Rails.cache,
         nonce_ttl: 900
```

`nonce_cache` is any object responding to `#read`, `#write(key, value,
expires_in:)` and `#delete` — `Rails.cache` satisfies this. The gem does not
depend on Rails; the cache is injected. `nonce_ttl` is in seconds and only needs
to outlive one login round trip.

The cache must be a real one. A no-op cache accepts the write and returns
nothing on read, so the nonce cannot be claimed and every login fails at the
callback with `Returned nonce did not match.` — the store cannot distinguish
this from an expired nonce, and the write guard does not fire because a no-op
write reports success. Rails applications commonly set
`config.cache_store = :null_store` in development and test while configuring a
real store only in production; check the environment you are testing in.

#### Carrying state across the callback

Anything else the session cannot hold across the cross-site POST can travel with
the nonce. Subclass the store and override `payload` and `on_claim`:

```ruby
class AzureNonceStore < OmniAuth::AzureActiveDirectory::CacheNonceStore
  def payload
    { 'return_to' => strategy.session['user_return_to'] }
  end

  def on_claim(payload)
    strategy.session['user_return_to'] = payload['return_to'] if payload['return_to']
  end
end
```

Then pass `nonce_store: AzureNonceStore`.

#### Writing your own store

Subclass `OmniAuth::AzureActiveDirectory::NonceStore` and implement `store(nonce)`
and `claim(nonce)`. The class is instantiated with the strategy, so `strategy`,
`options` and `session` are available. `store` must raise if it cannot persist:
a nonce that was never stored resurfaces at the callback as a nonce mismatch,
which sends whoever debugs it towards the JWT rather than the storage.

Nonces are one-time use — `claim` must remove the nonce so it cannot be claimed
twice. Note that `CacheNonceStore` reads and then deletes, which is not atomic:
two callbacks racing on the same nonce could both claim it. Closing that window
needs a primitive the generic cache interface does not expose (Redis `GETDEL`
or a Lua script); if you need it, implement `claim` against your backend
directly.

### Auth Hash

OmniAuth AzureAD tries to be consistent with the auth hash schema recommended by OmniAuth. [https://github.com/intridea/omniauth/wiki/Auth-Hash-Schema](https://github.com/intridea/omniauth/wiki/Auth-Hash-Schema).

Here's an example of an authentication hash available in the callback. You can access this hash as `request.env['omniauth.auth']`.

```
  :provider => "azureactivedirectory",
  :uid => "123456abcdef",
  :info => {
    :name => "John Smith",
    :email => "jsmith@contoso.net",
    :first_name => "John",
    :last_name => "Smith"
  },
  :credentials => {
    :code => "ffdsjap9fdjw893-rt2wj8r9r32jnkdsflaofdsa9"
  },
  :extra => {
    :session_state => '532fgdsgtfera32',
    :raw_info => {
      :id_token => "fjeri9wqrfe98r23.fdsaf121435rt.f42qfdsaf",
      :id_token_claims => {
        "aud" => "fdsafdsa-fdsafd-fdsa-sfdasfds",
        "iss" => "https://sts.windows.net/fdsafdsa-fdsafdsa/",
        "iat" => 53315113,
        "nbf" => 53143215,
        "exp" => 53425123,
        "ver" => "1.0",
        "tid" => "5ffdsa2f-dsafds-sda-sds",
        "oid" => "fdsafdsaafdsa",
        "upn" => "jsmith@contoso.com",
        "sub" => "123456abcdef",
        "nonce" => "fdsaf342rfdsafdsafsads"
      },
      :id_token_header => {
        "typ" => "JWT",
        "alg" => "RS256",
        "x5t" => "fdsafdsafdsafdsa4t4er32",
        "kid" => "tjiofpjd8ap9fgdsa44"
      }
    }
  }
```

## License

Copyright (c) Microsoft Corporation. Licensed under the MIT License.
