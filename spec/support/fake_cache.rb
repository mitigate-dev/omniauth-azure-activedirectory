# Minimal stand-in for Rails.cache: #read, #write(expires_in:) and #delete.
class FakeCache
  attr_reader :writes

  def initialize(write_result: true)
    @data = {}
    @writes = []
    @write_result = write_result
  end

  def write(key, value, **opts)
    @writes << [key, value, opts]
    return @write_result unless @write_result
    @data[key] = value
    @write_result
  end

  def read(key)
    @data[key]
  end

  def delete(key)
    !@data.delete(key).nil?
  end

  def key?(key)
    @data.key?(key)
  end
end
