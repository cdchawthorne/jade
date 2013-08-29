require 'optparse'
require 'jade_database'
require 'jade_exceptions'

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
           #{description}}

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
      raise JadeExceptions::BadUsageError.new(error, detailed_help)
    end

    if not @num_args_range === plain_args.length
      raise JadeExceptions::BadUsageError.new("Incorrect number of arguments",
                                              detailed_help)
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

class JadeRunner
  DEFAULT_DB_LOCATION = Dir.home + "/.jade"

  BACKUP = Command.new(
    lambda { |plain_args, options|
      db_location = options.fetch('db_location', DEFAULT_DB_LOCATION)
      JadeDatabase.new(db_location).backup(*plain_args)
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
      db_location = options.fetch('db_location', DEFAULT_DB_LOCATION)
      JadeDatabase.new(db_location).restore_latest(*plain_args)
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
      db_location = options.fetch('db_location', DEFAULT_DB_LOCATION)

      for row in JadeDatabase.new(db_location).list_backups(*plain_args)
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
      elsif COMMANDS_BY_NAME[plain_args[0]]
        $stdout.puts COMMANDS_BY_NAME[plain_args[0]].detailed_help
      else
        raise JadeExceptions::BadUsageError.new("Command not found",
                                                jade_usage)
      end
    },
    CommandMetadata.new(
      %q{jade help [COMMAND]},
      %q{Present a list of commands; if present, show help for COMMAND},
      0..1,
      []
    )
  )

  CREATE_DB = Command.new(
    lambda { |plain_args, options|
      JadeDatabase.create(plain_args[0])
    },
    CommandMetadata.new(
      %q{jade create_db DB_LOCATION},
      %q{Create a new jade database at DB_LOCATION},
      1,
      []
    )
  )

  COMMANDS_BY_NAME = {
    'list_backups' => LIST_BACKUPS,
    'backup' => BACKUP,
    'restore_latest' => RESTORE_LATEST,
    'help' => HELP,
    'create_db' => CREATE_DB,
  }

  def JadeRunner.run(args)
    begin
      if args.empty?
        raise JadeExceptions::BadUsageError.new("No command given", jade_usage)
      end

      command_name = args.shift
      if COMMANDS_BY_NAME[command_name]
        COMMANDS_BY_NAME[command_name].run(args)
      else
        raise JadeExceptions::BadUsageError.new("Command not found",
                                                jade_usage)
      end
    rescue JadeExceptions::JadeException => error
      $stderr.puts "ERROR:"
      $stderr.puts error.message
      exit(1)
    end
  end

  def JadeRunner.jade_usage
    ret = %Q{Usage: jade COMMAND ARGS

Commands:
}

    COMMANDS_BY_NAME.sort.each { |_, command|
      ret << " " * 4 << command.usage << "\n"
      ret << " " * 8 << command.description << "\n"
    }

    ret
  end
end

JadeRunner.run(ARGV)
