module JadeExceptions
  class JadeException < Exception
  end

  class FileNotFoundError < JadeException
    def initialize(filename)
      super "File not found: #{filename}"
    end
  end

  class BackupNotFoundError < JadeException
    def initialize(backup_id)
      super "No backups with ID #{backup_id}"
    end
  end

  class BadUsageError < JadeException
    def initialize(error_msg, usage)
      super "Bad usage: #{error_msg}\n#{usage}"
    end
  end

  class CorruptedDatabaseError < JadeException
    def initialize(db_location)
      super "Corrupted database: #{db_location}"
    end
  end

  class DatabaseCreationError < JadeException
    def initialize(message)
      super "Database creation failed: #{message}"
    end
  end

  class RestorationError < JadeException
    def initialize(error_code)
      super "Restoration failed: extracting tar failed with exit code" \
              "#{error_code}"
    end
  end

  class NoBackupsError < JadeException
    def initialize(target)
      super "No backups found for #{target}"
    end
  end

  class PushError < JadeException
    def initialize(db_location, remote, error_code)
      super "Push failed: rsync of #{db_location} to #{remote} failed with " \
        "exit code #{error_code}"
    end
  end

  class PullError < JadeException
    def initialize(target_dir, remote, error_code)
      super "Pull failed: rsync of #{remote} to #{target_dir} failed with " \
        "exit code #{error_code}"
    end
  end

  class BadRemoteDatabaseError < JadeException
    def initialize(remote)
      super "#{remote} is not a valid jade database"
    end
  end

  class NoRemoteDatabaseError < JadeException
    def initialize(db_location)
      super "No default remote database in #{db_location}"
    end
  end

  class BadDestError < JadeException
    def initialize(message)
      super "Bad destination: #{message}"
    end
  end
end
