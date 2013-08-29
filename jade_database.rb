require 'sqlite3'
require 'jade_exceptions'

class JadeDatabase
  def initialize(location)
    @db = SQLite3::Database.new(location + "/backups.db")
    @archives_dir = location + "/backup_archives"
  end

  def backup(source, description)
    @db.execute('INSERT INTO backups (source, description) VALUES (?, ?)',
                File.absolute_path(source), description)
    backup_id = @db.last_insert_row_id
    archive_location = "#{@archives_dir}/#{backup_id}.tar.gz"
    if not system("tar", "-czPf", archive_location, File.absolute_path(source))
      @db.execute('DELETE FROM backups WHERE ROWID = ?', backup_id)
      begin
        File.delete archive_location
      rescue Errno::ENOENT
      end

      raise JadeExceptions::FileNotFoundError.new(File.absolute_path(source))
    end
  end

  def restore_latest(target)
    sql = %q{
      SELECT ROWID, timestamp, description FROM backups
      WHERE ? LIKE source || '%' ORDER BY timestamp DESC
    }
    backup_id, timestamp, description =
      @db.get_first_row(sql, File.absolute_path(target))

    if not backup_id
      raise JadeExceptions::NoBackupsError.new(target)
    end

    $stdout.puts "Restore backup \"#{description}\" from #{timestamp}? (y/n)"
    if $stdin.readline.chomp == 'y'
      archive_location = "#{@archives_dir}/#{backup_id}.tar.gz"
      system("tar", "-xzPf", archive_location, File.absolute_path(target))
    end
  end

  def list_backups(target=nil)
    if target
      sql = %q{
        SELECT timestamp, description FROM backups
        WHERE ? LIKE source || '%' ORDER BY timestamp DESC
      }
      @db.execute(sql, File.absolute_path(target))
    else
      sql = %q{
        SELECT timestamp, source, description FROM backups
        ORDER BY timestamp DESC
      }
      @db.execute(sql)
    end
  end
end
