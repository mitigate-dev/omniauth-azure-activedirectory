# Minimal stand-in for Rails.cache: #read, #write(expires_in:) and #delete.
class FakeCache
  attr_reader :writes

  def initialize(write_result: true, raise_on: nil, error: nil)
    @data = {}
    @writes = []
    @write_result = write_result
    @raise_on = Array(raise_on)
    @error = error || RuntimeError.new('OOM command not allowed')
  end

  def maybe_raise!(op)
    raise @error if @raise_on.include?(op)
  end

  def write(key, value, **opts)
    maybe_raise!(:write)
    @writes << [key, value, opts]
    return @write_result unless @write_result
    @data[key] = value
    @write_result
  end

  def read(key)
    maybe_raise!(:read)
    @data[key]
  end

  def delete(key)
    maybe_raise!(:delete)
    !@data.delete(key).nil?
  end

  def key?(key)
    @data.key?(key)
  end
end
