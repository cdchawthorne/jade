require 'jade_database'
require 'jade_exceptions'

class JadeBackup
  def initialize(db_location, backup_id)
    db = JadeDatabase.new(db_location)
    sql = %q{
      SELECT timestamp, source, description FROM backups WHERE ROWID = ?;
    }
    timestamp, source, description = db.execute_sql(sql, backup_id).first

    raise JadeExceptions::BackupNotFoundError.new(backup_id) unless timestamp

    @db = db
    @backup_id = backup_id
    @timestamp = timestamp
    @source = source
    @description = description
    @contents = nil
  end

  def JadeBackup.new_backup(db_location, source, description=nil)
    db = JadeDatabase.new(db_location)

    sql = %q{
      INSERT INTO backups (source, description) VALUES (?, ?);
    }
    db.execute_sql(sql, File.absolute_path(source), description)

    backup_id = db.last_insert_row_id
    archive_location = db.get_archive_location(backup_id)
    success = system("tar", "-czPf", archive_location,
                     File.absolute_path(source))

    unless success
      begin
        File.delete(db.get_archive_location(backup_id))
      rescue Errno::ENOENT
      end

      raise JadeExceptions::FileNotFoundError.new(File.absolute_path(source))
    end

    JadeBackup.new(db_location, backup_id)
  end

  def JadeBackup.list_backups(db_location, target=nil)
    db = JadeDatabase.new(db_location)
    if target
      sql = %q{
        SELECT ROWID FROM backups WHERE source = ? ORDER BY timestamp DESC;
      }

      backup_ids = db.execute_sql(sql, File.absolute_path(target)).flatten
    else
      sql = %q{SELECT ROWID FROM backups ORDER BY timestamp DESC;}
      backup_ids = db.execute_sql(sql).flatten
    end

    backup_ids.collect { |backup_id| JadeBackup.new(db_location, backup_id) }
  end

  def restore(file=nil)
    file = @source unless file
    $stdout.puts "Restore #{target} from the following backup?"
    $stdout.puts format
    $stdout.print "(y/n) "

    if $stdin.readline.chomp == 'y'
      archive_location = @db.get_archive_location(@backup_id)

      success = system("tar", "-xzPf", archive_location,
                       File.absolute_path(file))

      raise JadeExceptions::RestorationError.new($?.exitstatus) unless success
    end
  end

  def delete
    sql = %q{DELETE FROM backups WHERE ROWID = ?;}
    @db.execute_sql(sql, @backup_id)
    begin
      File.delete(@db.get_archive_location(@backup_id))
    rescue Errno::ENOENT
    end
  end

  def dump_archive(io_object)
    archive = File.new(@db.get_archive_location(@backup_id))
    while chars = archive.read(65536)
      io_object.write(chars)
    end
  end

  def format
    "ID: #{@backup_id}\nTimestamp: #{@timestamp}\nSource: #{@source}\n" \
      "Description: #{@description}"
  end

  def format_verbose
    formatted = format
    formatted << "\nContents:"
    contents.each { |file|
      formatted << "\n#{file}"
    }
    formatted
  end

  def contents
    fetch_contents unless @contents
    @contents
  end

  def fetch_contents
    archive_location = @db.get_archive_location(@backup_id)
    @contents = IO.popen(["tar", "-tPf", archive_location]) { |f|
      f.readlines.collect { |line| line.chomp }
    }
  end

  private :fetch_contents
end
