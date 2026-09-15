$LOAD_PATH.push File.expand_path('../lib', __FILE__)
require 'omniauth/azure_activedirectory/version'

Gem::Specification.new do |s|
  s.name            = 'omniauth-azure-activedirectory'
  s.version         = OmniAuth::AzureActiveDirectory::VERSION
  s.author          = 'Microsoft Corporation'
  s.email           = 'nugetaad@microsoft.com'
  s.summary         = 'Azure Active Directory strategy for OmniAuth'
  s.description     = 'Allows developers to authenticate to AAD'
  s.homepage        = 'https://github.com/AzureAD/omniauth-azure-activedirectory'
  s.license         = 'MIT'

  s.files           = `git ls-files`.split("\n")
  s.require_paths   = ['lib']

  s.add_runtime_dependency 'base64', '~> 0.2'
  s.add_runtime_dependency 'jwt', '>= 2.2', '< 3'
  s.add_runtime_dependency 'omniauth', '>= 1.1', '< 3'

  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rspec', '~> 3.3'
  s.add_development_dependency 'rubocop', '~> 0.32'
  s.add_development_dependency 'simplecov', '~> 0.10'
  s.add_development_dependency 'webmock', '~> 3.0'
end
