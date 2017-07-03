module Joint
  class AttachmentProxy
    def initialize(instance, name)
      @instance, @name = instance, name
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

    def files_id
      grid_io.info.id
    end

    def file_length
      grid_io.info.length
    end

    def read
      @instance.fs_bucket.open_download_stream(id).read
      # grid_io.data
    end

    def nil?
      !@instance.send("#{@name}?")
    end
    alias_method :blank?, :nil?

    def grid_io
      @grid_io ||= @instance.fs_bucket.find_one(_id: id)
    end

    def method_missing(method, *args, &block)
      grid_io.info.send(method, *args, &block)
    end
  end
end
