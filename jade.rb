# TODO: use exceptions
require 'sqlite3'
require 'optparse'

JADE_DIR = Dir.home + "/.jade"
BACKUPS_DB = JADE_DIR + "/backups.db"
BACKUPS_DIR = JADE_DIR + "/backup_archives"

class JadeDatabase
  DEFAULT_LOCATION = Dir.home + "/.jade"

  def initialize(location=DEFAULT_LOCATION)
    @db = SQLite3::Database.new(location + "/backups.db")
  end

  def backup(source, description)
    @db.execute('INSERT INTO backups (source, description) VALUES (?, ?)',
                File.absolute_path(source), description)
    backup_id = @db.last_insert_row_id
    archive_location = "#{BACKUPS_DIR}/#{backup_id}.tar.gz"
    if not system("tar", "-czPf", archive_location, File.absolute_path(source))
      @db.execute('DELETE FROM backups WHERE ROWID = ?', backup_id)
      begin
        File.delete archive_location
      rescue Errno::ENOENT
      end

      $stderr.puts "ERROR: backup failed"
      exit 1
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
      $stderr.puts "ERROR: no backups for #{target}"
      exit 1
    end

    $stdout.puts "Restore backup \"#{description}\" from #{timestamp}? (y/n)"
    if $stdin.readline.chomp == 'y'
      archive_location = "#{BACKUPS_DIR}/#{backup_id}.tar.gz"
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

class CommandMetadata
  attr_reader(:usage, :description)

  def initialize(usage, description, num_args_range, option_signatures)
    @num_args_range = num_args_range
    @usage = usage
    @description = description
    @options = {}
    @plain_args = []
    @parser = OptionParser.new { |opts|
      opts.banner = %Q{Usage: #{usage}
        #{description}
      }

      if not option_signatures.empty?
        opts.separator ""
        opts.separator "Options:"
      end

      for option_name, option_args in option_signatures
        opts.on(*option_args) { |val|
          @options[option_name] = val
        }
      end
    }
  end

  def parse_args(args)
    begin
      plain_args = @parser.parse(args)
    rescue OptionParser::InvalidOption => error
      $stderr.puts error
      $stderr.puts @parser
      exit 1
    end

    if not @num_args_range === plain_args.length
      $stderr.puts "ERROR: incorrect number of arguments"
      $stderr.puts @parser
      exit 1
    end

    return plain_args, @options
  end

  def detailed_help
    @parser.to_s
  end
end

class Command
  def initialize(execute, metadata)
    @execute = execute
    @metadata = metadata
  end

  def run(args)
    plain_args, options = @metadata.parse_args(args)
    @execute.call(plain_args, options)
  end

  def detailed_help
    @metadata.detailed_help
  end

  def usage
    @metadata.usage
  end

  def description
    @metadata.description
  end
end

class CommandRunner

  BACKUP = Command.new(
    lambda { |plain_args, options|
      jade_db = options['db_location'] ?
                JadeDatabase.new(options['db_location']) :
                JadeDatabase.new

      jade_db.backup(*plain_args)
    },
    CommandMetadata.new(
      %q{jade backup FILENAME DESCRIPTION},
      %q{Make a backup of FILENAME},
      2,
      [
        ['db_location', ['-d', '--database-location DB_LOCATION',
                         'Specify the jade database to use']]
      ]
    )
  )

  RESTORE_LATEST = Command.new(
    lambda { |plain_args, options|
      jade_db = options['db_location'] ?
                JadeDatabase.new(options['db_location']) :
                JadeDatabase.new

      jade_db.restore_latest(*plain_args)
    },
    CommandMetadata.new(
      %q{jade restore_latest FILENAME},
      %q{Restore the most recent backup of FILENAME},
      1,
      [
        ['db_location', ['-d', '--database-location DB_LOCATION',
                         'Specify the jade database to use']]
      ]
    )
  )

  LIST_BACKUPS = Command.new(
    lambda { |plain_args, options|
      jade_db = options['db_location'] ?
                JadeDatabase.new(options['db_location']) :
                JadeDatabase.new

      for row in jade_db.list_backups(*plain_args)
        $stdout.puts(row.join('    |    '))
      end
    },
    CommandMetadata.new(
      %q{jade list_backups [FILENAME]},
      %q{List all backups; if present, only show backups of FILENAME},
      0..1,
      [
        ['db_location', ['-d', '--database-location DB_LOCATION',
                         'Specify the jade database to use']]
      ]
    )
  )

  HELP = Command.new(
    lambda { |plain_args, options|
      if plain_args.empty?
        $stdout.puts jade_usage
      else
        if COMMANDS_BY_NAME[plain_args[0]]
          $stdout.puts COMMANDS_BY_NAME[plain_args[0]].detailed_help
        else
          $stderr.puts "ERROR: command not found: #{plain_args[0]}"
          exit 1
        end
      end
    },
    CommandMetadata.new(
      %q{jade help [COMMAND]},
      %q{Present a list of commands; if present, show help for COMMAND},
      0..1,
      []
    )
  )

  COMMANDS_BY_NAME = {
    'list_backups' => LIST_BACKUPS,
    'backup' => BACKUP,
    'restore_latest' => RESTORE_LATEST,
    'help' => HELP,
  }

  def CommandRunner.run(args)
    if args.empty?
      $stderr.puts jade_usage
      exit 1
    end

    command_name = args.shift
    if COMMANDS_BY_NAME[command_name]
      COMMANDS_BY_NAME[command_name].run(args)
    else
      $stderr.puts jade_usage
      exit 1
    end
  end

  def CommandRunner.print_help(command_name)
    $stdout.puts COMMANDS_BY_NAME[command_name].help
  end

  def CommandRunner.jade_usage
    ret = %Q{Usage: #{$0} COMMAND ARGS

Commands:
}

    COMMANDS_BY_NAME.sort.each { |_, command|
      ret << " " * 4 << command.usage << "\n"
      ret << " " * 8 << command.description << "\n"
    }

    ret
  end
end

CommandRunner.run(ARGV)
