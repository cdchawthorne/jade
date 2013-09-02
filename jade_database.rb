require 'sqlite3'
require 'jade_exceptions'
require 'fileutils'
require 'tmpdir'

class JadeDatabase

  def JadeDatabase.create(location)
    begin
      Dir.mkdir location
    rescue SystemCallError => error
      raise JadeExceptions::DatabaseCreationError.new(error.message)
    end

    begin
      Dir.mkdir(location + "/backup_archives")
    rescue SystemCallError
      Dir.delete(location)
      raise JadeExceptions::DatabaseCreationError.new(error.message)
    end

    sql_db = SQLite3::Database.new(location + "/backups.db")

    sql = %q{
      CREATE TABLE backups (
        timestamp TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
        source TEXT NOT NULL, description TEXT
      );
    }
    sql_db.execute(sql)

    sql = %q{CREATE TABLE settings ( remote TEXT);}
    sql_db.execute(sql)

    sql = %q{INSERT INTO settings DEFAULT VALUES;}
    sql_db.execute(sql)
  end

  def initialize(location)
    @location = location
    @sql_db = SQLite3::Database.new("#{location}/backups.db")
  end

  def execute_sql(*args)
    begin
      @sql_db.execute(*args)
    rescue SQLite3::SQLException
      raise JadeExceptions::CorruptedDatabaseError.new(@sql_db_location)
    end
  end

  def push(remote=nil)
    remote = get_default_remote unless remote
    raise JadeExceptions::NoRemoteDatabaseError.new(@location) unless remote
    success = system('rsync', '-avz', '--delete', "#{@location}/", remote)
    unless success
      raise JadeExceptions::PushError.new(@location, remote, $?.exitstatus)
    end
  end

  def pull(remote=nil)
    remote = get_default_remote unless remote
    raise JadeExceptions::NoRemoteDatabaseError.new(@location) unless remote

    dir = Dir.mktmpdir("jade")
    begin
      success = system('rsync', '-avz', '--delete', "#{remote}/", dir)
      unless success
        raise JadeExceptions::PullError.new(dir, remote, $?.exitstatus)
      end
      unless JadeDatabase.new(dir).valid?
        raise JadeExceptions::BadRemoteDatabaseError.new(remote)
      end
      FileUtils.rm_rf(@location)
      FileUtils.mv(dir, @location)
    ensure
      FileUtils.rm_rf(dir)
    end

  end

  def valid?
    return false unless File.directory?("#{@location}/backup_archives")
    fs_archives = Dir.entries("#{@location}/backup_archives") - [".", ".."]
    fs_archives.collect! { |file| "#{@location}/backup_archives/#{file}" }

    begin
      execute_sql('SELECT * FROM settings;')
    rescue JadeExceptions::CorruptedDatabaseError
      return false
    end

    begin
      rowids = execute_sql('SELECT ROWID FROM backups;').flatten
    rescue JadeExceptions::CorruptedDatabaseError
      return false
    end

    db_archives = rowids.collect { |rowid| get_archive_location(rowid) }

    return false unless db_archives == fs_archives

    true
  end


  def get_default_remote
    rows = execute_sql(%q{SELECT remote FROM settings;})
    unless rows.length == 1
      raise JadeException::CorruptedDatabaseError.new(@sql_db_location)
    end
    rows.first.first
  end

  def set_default_remote(remote_location)
    execute_sql(%q{UPDATE settings SET remote = ?;}, remote_location)
  end

  def get_archive_location(backup_id)
    "#{@location}/backup_archives/#{backup_id}.tar.gz"
  end

  def last_insert_row_id
    @sql_db.last_insert_row_id
  end
end
