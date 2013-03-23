require 'henzell/learndb_query'
require 'query/grammar'
require 'set'
require 'cmd/user_defined_command'

module Henzell
  class Commands
    def initialize(commands_file)
      @commands_file = commands_file
      @user_commands = { }
      @commands = { }
      self.load
    end

    def builtin?(command_name)
      @commands[command_name] || command_name == '??'
    end

    def user_defined?(command_name)
      @user_commands[command_name]
    end

    def include?(command_name)
      builtin?(command_name) || user_defined?(command_name)
    end

    def learndb_query(arguments)
      [0, Henzell::LearnDBQuery.query(arguments), '']
    end

    def execute(command_line, default_nick='???')
      unless command_line =~ /^(\S+)(?:(\s+(.*)))?/
        raise StandardError, "Bad command line: #{command_line}"
      end
      command = $1.downcase
      arguments = $2 || ''

      if command == '??'
        return learndb_query(arguments)
      end

      execute_command(command, arguments, default_nick)
    end

    def execute_command(command, arguments, default_nick)
      seen_commands = Set.new
      extra_args = []
      while true
        if seen_commands.include?(command)
          raise "Bad command (recursive): #{command}"
        end

        seen_commands << command
        unless self.include?(command)
          raise StandardError, "Bad command: #{command} #{arguments}"
        end

        if self.user_defined?(command)
          command, args = Cmd::UserDefinedCommand.expand(command)
          extra_args << arguments
          arguments = args
          next
        end

        command_script = File.join(Config.root, "commands", @commands[command])
        target = default_nick

        extra_args = extra_args.reverse
        ENV['EXTRA_ARGS'] = extra_args.join(' ')
        ENV['EXTRA_ARGS_PARENTHESIZED'] = extra_args.map { |arg|
          Query::Grammar::OPEN_PAREN + " " + arg + " " +
          Query::Grammar::CLOSE_PAREN
        }.join(' ')
        command_line = [command, arguments].join(' ')
        system_command_line =
          %{#{command_script} #{quote(target)} #{quote(default_nick)} } +
          %{#{quote(command_line)} ''}
        output = %x{#{system_command_line}}
        exit_code = $? >> 8
        return [exit_code, output, system_command_line]
      end
    end

    def quote(text)
      text.gsub(/[^\w]/) { |t|
        '\\' + t
      }
    end

    def load
      File.open(@commands_file, 'r') { |file|
        file.each { |line|
          line = line.strip
          next if line =~ /^#/
          if line =~ /^(\S+) (.*)/
            @commands[$1.downcase] = $2
          end
        }
      }

      Cmd::UserDefinedCommand.each { |command|
        @user_commands[command.name] = command
      }
    end
  end
end