module Joint
  class AttachmentProxy
    # The attachment this proxy stands for. Not to be confused with #name, which is the
    # stored file's name. Lets a record find the proxies it needs to invalidate without
    # having to know each attachment's accessor_name.
    attr_reader :attachment_name

    def initialize(instance, name)
      @instance, @name = instance, name
      @attachment_name = name
    end

    def id
      @instance.send("#{@name}_id")
    end

    def name
      @instance.send("#{@name}_name")
    end

    def size
      @instance.send("#{@name}_size")
    end

    def type
      @instance.send("#{@name}_type")
    end

    def extension
      MIME::Types[type].first.try(:preferred_extension)
    end

    def crc32
      Zlib.crc32([id, name, size, type].compact.join())
    rescue
      0
    end

    def nil?
      !@instance.send("#{@name}?")
    end
    alias_method :blank?, :nil?

    def grid_io
      @grid_io ||= @instance.grid.open_download_stream(id)
    end

    def method_missing(method, *args, &block)
      grid_io.send(method, *args, &block)
    end
  end
end
