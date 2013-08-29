module JadeExceptions
  class JadeException < Exception
  end

  class FileNotFoundError < JadeException
    def initialize(filename)
      super "File not found: #{filename}"
    end
  end

  class NoBackupsError < JadeException
    def initialize(filename)
      super "No backups for #{filename}"
    end
  end

  class BadUsageError < JadeException
    def initialize(error_msg, usage)
      super "Bad usage: #{error_msg}\n#{usage}"
    end
  end
end
