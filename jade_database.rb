require 'sqlite3'
require 'jade_exceptions'

class JadeDatabase
  def JadeDatabase.create(location)
    begin
      Dir.mkdir location
    rescue SystemCallError => error
      raise DatabaseCreationError(error.message)
    end

    begin
      Dir.mkdir(location + "/backup_archives")
    rescue SystemCallError
      Dir.delete(location)
      raise DatabaseCreationError(error.message)
    end

    sql_db = SQLite3::Database.new(location + "/backups.db")

    sql = %q{
      CREATE TABLE backups (
        timestamp TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
        source TEXT NOT NULL, description TEXT
      );
    }
    sql_db.execute(sql)
  end

  def initialize(location)
    @location = location
    @sql_db = SQLite3::Database.new(location + "/backups.db")
  end

  def backup(source, description)
    begin
      sql = %q{INSERT INTO backups (source, description) VALUES (?, ?)}
      @sql_db.execute(sql, File.absolute_path(source), description)
    rescue SQLite3::SQLException
      raise JadeExceptions::CorruptedDatabaseError(@sql_db_location)
    end

    backup_id = @sql_db.last_insert_row_id
    archive_location = "#{@location}/backup_archives/#{backup_id}.tar.gz"
    if not system("tar", "-czPf", archive_location, File.absolute_path(source))
      @sql_db.execute('DELETE FROM backups WHERE ROWID = ?', backup_id)
      begin
        File.delete archive_location
      rescue Errno::ENOENT
      end

      raise JadeExceptions::FileNotFoundError.new(File.absolute_path(source))
    end
  end

  def restore_latest(target)
    sql = %q{
      SELECT ROWID, timestamp, source, description FROM backups
      WHERE ? LIKE source || '%' ORDER BY timestamp DESC
    }

    begin
      backup_id, timestamp, source, description =
        @sql_db.get_first_row(sql, File.absolute_path(target))
    rescue SQLite3::SQLException
      raise JadeExceptions::CorruptedDatabaseError(@location)
    end

    if not backup_id
      raise JadeExceptions::NoBackupsError.new(target)
    end

    $stdout.print "Restore #{File.absolute_path target} from backup" +
                  " \"#{description}\" of #{source} at #{timestamp}? (y/n) "
    if $stdin.readline.chomp == 'y'
      archive_location = "#{@location}/backup_archives/#{backup_id}.tar.gz"
      success = system("tar", "-xzPf", archive_location,
                       File.absolute_path(target))
      if not success
        raise CorruptedDatabaseError(@location)
      end
    end
  end

  def list_backups(target=nil)
    if target
      sql = %q{
        SELECT timestamp, description FROM backups
        WHERE ? LIKE source || '%' ORDER BY timestamp DESC
      }
      begin
        @sql_db.execute(sql, File.absolute_path(target))
      rescue SQLite3::SQLException
        raise CorruptedDatabaseError(@location)
      end
    else
      sql = %q{
        SELECT timestamp, source, description FROM backups
        ORDER BY timestamp DESC
      }
      begin
        @sql_db.execute(sql)
      rescue SQLite3::SQLException
        raise CorruptedDatabaseError(@location)
      end
    end
  end
end
