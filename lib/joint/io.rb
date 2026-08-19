require 'stringio'

module Joint
  class IO
    attr_accessor :name, :content, :type, :size

    def initialize(attrs={})
      attrs.each { |key, value| send("#{key}=", value) }
      @type ||= 'plain/text'
    end

    def content=(value)
      @io = StringIO.new(value || nil)
      @size = value ? value.size : 0
    end

    def read(*args)
      @io.read(*args)
    end

    # The Mongo driver chunks an upload with `read(chunk_size) until eof?`, so an IO that
    # cannot answer this is not usable as an attachment.
    def eof?
      @io.eof?
    end

    def rewind
      @io.rewind if @io.respond_to?(:rewind)
    end

    alias path name
  end
end