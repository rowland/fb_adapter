# Author: Ken Kunz <kennethkunz@gmail.com>
# Converted from FireRuby to Fb extension by Brent Rowland <rowland@rowlandresearch.com>

require 'active_record/connection_adapters/abstract_adapter'
require 'base64'

module ActiveRecord
  class << Base
    def fb_connection(config) # :nodoc:
      require_library_or_gem 'fb'
      config = config.symbolize_keys.merge(:downcase_names => true)
      unless config.has_key?(:database)
        raise ArgumentError, "No database specified. Missing argument: database."
      end      
      config[:database] = File.expand_path(config[:database]) if config[:host] =~ /localhost/i
      config[:database] = "#{config[:host]}:#{config[:database]}" if config[:host]
      db = Fb::Database.new(config)
      begin
        connection = db.connect
      rescue
        require 'pp'; pp config
        connection = config[:create] ? db.create.connect : (raise ConnectionNotEstablished, "No Firebird connections established.")
      end
      ConnectionAdapters::FbAdapter.new(connection, logger, config)
    end
  end

  module ConnectionAdapters
    class FbColumn < Column # :nodoc:
      VARCHAR_MAX_LENGTH = 32_765

      def initialize(name, domain, type, sub_type, length, precision, scale, default_source, null_flag)
        #puts "*** #{type} ~~~ #{sub_type}"
        @firebird_type = Fb::SqlType.from_code(type, sub_type || 0)
        super(name.downcase, nil, @firebird_type, !null_flag)
        @default = parse_default(default_source) if default_source
        @limit = (@firebird_type == 'BLOB') ? 10 * 1024 * 1024 : length
        @domain, @sub_type, @precision, @scale = domain, sub_type, precision, scale
      end

      def type
        if @domain =~ /BOOLEAN/
          :boolean
        elsif @type == :binary and @sub_type == 1
          :text
        else
          @type
        end
      end

      # Submits a _CAST_ query to the database, casting the default value to the specified SQL type.
      # This enables Firebird to provide an actual value when context variables are used as column
      # defaults (such as CURRENT_TIMESTAMP).
      def default
        if @default
          sql = "SELECT CAST(#{@default} AS #{column_def}) FROM RDB$DATABASE"
          connection = ActiveRecord::Base.active_connections.values.detect { |conn| conn && conn.adapter_name == 'Fb' }
          if connection
            type_cast connection.select_one(sql)['cast']
          else
            raise ConnectionNotEstablished, "No Firebird connections established."
          end
        end
      end

      def self.value_to_boolean(value)
        %W(#{FirebirdAdapter.boolean_domain[:true]} true t 1).include? value.to_s.downcase
      end

      private
        def parse_default(default_source)
          default_source =~ /^\s*DEFAULT\s+(.*)\s*$/i
          return $1 unless $1.upcase == "NULL"
        end

        def column_def
          case @firebird_type
            #when 'BLOB'               then "VARCHAR(#{VARCHAR_MAX_LENGTH})"
            when 'CHAR', 'VARCHAR'    then "#{@firebird_type}(#{@limit})"
            when 'NUMERIC', 'DECIMAL' then "#{@firebird_type}(#{@precision},#{@scale.abs})"
            #when 'DOUBLE'             then "DOUBLE PRECISION"
            else @firebird_type
          end
        end

        def simplified_type(field_type)
          if field_type == 'TIMESTAMP'
            :datetime
          else
            super
          end
        end
    end

    # The Fb adapter relies on the Fb extension.
    #
    # == Usage Notes
    #
    # === Sequence (Generator) Names
    # The Fb adapter supports the same approach adopted for the Oracle
    # adapter. See ActiveRecord::Base#set_sequence_name for more details.
    #
    # Note that in general there is no need to create a <tt>BEFORE INSERT</tt>
    # trigger corresponding to a Firebird sequence generator when using
    # ActiveRecord. In other words, you don't have to try to make Firebird
    # simulate an <tt>AUTO_INCREMENT</tt> or +IDENTITY+ column. When saving a
    # new record, ActiveRecord pre-fetches the next sequence value for the table
    # and explicitly includes it in the +INSERT+ statement. (Pre-fetching the
    # next primary key value is the only reliable method for the Fb
    # adapter to report back the +id+ after a successful insert.)
    #
    # === BOOLEAN Domain
    # Firebird 1.5 does not provide a native +BOOLEAN+ type. But you can easily
    # define a +BOOLEAN+ _domain_ for this purpose, e.g.:
    #
    #  CREATE DOMAIN D_BOOLEAN AS SMALLINT CHECK (VALUE IN (0, 1));
    #
    # When the Fb adapter encounters a column that is based on a domain
    # that includes "BOOLEAN" in the domain name, it will attempt to treat
    # the column as a +BOOLEAN+.
    #
    # By default, the Fb adapter will assume that the BOOLEAN domain is
    # defined as above.  This can be modified if needed.  For example, if you
    # have a legacy schema with the following +BOOLEAN+ domain defined:
    #
    #  CREATE DOMAIN BOOLEAN AS CHAR(1) CHECK (VALUE IN ('T', 'F'));
    #
    # ...you can add the following line to your <tt>environment.rb</tt> file:
    #
    #  ActiveRecord::ConnectionAdapters::Fb.boolean_domain = { :true => 'T', :false => 'F' }
    #
    # === Column Name Case Semantics
    # Firebird and ActiveRecord have somewhat conflicting case semantics for
    # column names.
    #
    # [*Firebird*]
    #   The standard practice is to use unquoted column names, which can be
    #   thought of as case-insensitive. (In fact, Firebird converts them to
    #   uppercase.) Quoted column names (not typically used) are case-sensitive.
    # [*ActiveRecord*]
    #   Attribute accessors corresponding to column names are case-sensitive.
    #   The defaults for primary key and inheritance columns are lowercase, and
    #   in general, people use lowercase attribute names.
    #
    # In order to map between the differing semantics in a way that conforms
    # to common usage for both Firebird and ActiveRecord, uppercase column names
    # in Firebird are converted to lowercase attribute names in ActiveRecord,
    # and vice-versa. Mixed-case column names retain their case in both
    # directions. Lowercase (quoted) Firebird column names are not supported.
    # This is similar to the solutions adopted by other adapters.
    #
    # In general, the best approach is to use unquoted (case-insensitive) column
    # names in your Firebird DDL (or if you must quote, use uppercase column
    # names). These will correspond to lowercase attributes in ActiveRecord.
    #
    # For example, a Firebird table based on the following DDL:
    #
    #  CREATE TABLE products (
    #    id BIGINT NOT NULL PRIMARY KEY,
    #    "TYPE" VARCHAR(50),
    #    name VARCHAR(255) );
    #
    # ...will correspond to an ActiveRecord model class called +Product+ with
    # the following attributes: +id+, +type+, +name+.
    #
    # ==== Quoting <tt>"TYPE"</tt> and other Firebird reserved words:
    # In ActiveRecord, the default inheritance column name is +type+. The word
    # _type_ is a Firebird reserved word, so it must be quoted in any Firebird
    # SQL statements. Because of the case mapping described above, you should
    # always reference this column using quoted-uppercase syntax
    # (<tt>"TYPE"</tt>) within Firebird DDL or other SQL statements (as in the
    # example above). This holds true for any other Firebird reserved words used
    # as column names as well.
    #
    # === Migrations
    # The Fb adapter does not currently support Migrations.
    #
    # == Connection Options
    # The following options are supported by the Fb adapter.
    #
    # <tt>:database</tt>::
    #   <i>Required option.</i> Specifies one of: (i) a Firebird database alias;
    #   (ii) the full path of a database file; _or_ (iii) a full Firebird
    #   connection string. <i>Do not specify <tt>:host</tt>, <tt>:service</tt>
    #   or <tt>:port</tt> as separate options when using a full connection
    #   string.</i>
    # <tt>:username</tt>::
    #   Specifies the database user. Defaults to 'sysdba'.
    # <tt>:password</tt>::
    #   Specifies the database password. Defaults to 'masterkey'.
    # <tt>:charset</tt>::
    #   Specifies the character set to be used by the connection. Refer to the
    #   Firebird documentation for valid options.
    class FbAdapter < AbstractAdapter
      @@boolean_domain = { :true => 1, :false => 0 }
      cattr_accessor :boolean_domain

      def initialize(connection, logger, connection_params=nil)
        super(connection, logger)
        @connection_params = connection_params
      end

      def adapter_name # :nodoc:
        'Fb'
      end

      # Returns true for Fb adapter (since Firebird requires primary key
      # values to be pre-fetched before insert). See also #next_sequence_value.
      def prefetch_primary_key?(table_name = nil)
        true
      end

      def default_sequence_name(table_name, primary_key) # :nodoc:
        "#{table_name}_seq"
      end


      # QUOTING ==================================================

      def quote(value, column = nil) # :nodoc:
        case value
          when String
            "@#{Base64.encode64(value).chop}@"
          when Float, Fixnum, Bignum then quote_number(value)
          when Date                  then quote_date(value)
          when Time, DateTime        then quote_timestamp(value)
          when NilClass              then "NULL"
          when TrueClass             then (column && column.type == :integer ? '1' : quoted_true)
          when FalseClass            then (column && column.type == :integer ? '0' : quoted_false)
          else                            quote_object(value)
        end
      end

      def quote_number(value)
        # "@#{Base64.encode64(value.to_s).chop}@"
        value.to_s
      end

      def quote_date(value)
        "@#{Base64.encode64(value.strftime('%Y-%m-%d')).chop}@"
      end

      def quote_timestamp(value)
        "@#{Base64.encode64(value.strftime('%Y-%m-%d %H:%M:%S')).chop}@"
      end

      def quote_string(string) # :nodoc:
        string.gsub(/'/, "''")
      end

      def quote_object(obj)
        return obj.respond_to?(:quoted_id) ? obj.quoted_id : "@#{Base64.encode64(obj.to_yaml).chop}@"
      end

      def quote_column_name(column_name) # :nodoc:
        %Q("#{ar_to_fb_case(column_name.to_s)}")
      end

      def quoted_true # :nodoc:
        quote(boolean_domain[:true])
      end

      def quoted_false # :nodoc:
        quote(boolean_domain[:false])
      end


      # CONNECTION MANAGEMENT ====================================

      def active?
        @connection.open?
      end

      def disconnect!
        @connection.close rescue nil
      end

      def reconnect!
        disconnect!
        @connection = Fb::Database.connect(@connection_params)
      end

      # DATABASE STATEMENTS ======================================

      def translate(sql)
        sql.gsub!(/\bIN\s+\(NULL\)/i, 'IS NULL')
        sql.sub!(/\bWHERE\s.*$/im) do |m|
          m.gsub(/\s=\s*NULL\b/i, ' IS NULL')
        end
        sql.gsub!(/\sIN\s+\([^\)]*\)/mi) do |m|
          m.gsub(/\(([^\)]*)\)/m) { |n| n.gsub(/\@(.*?)\@/m) { |n| "'#{quote_string(Base64.decode64(n[1..-1]))}'" } }
        end
        args = []
        sql.gsub!(/\@(.*?)\@/m) { |m| args << Base64.decode64(m[1..-1]); '?' }
        yield(sql, args) if block_given?
      end

      def expand(sql, args)
        sql + ', ' + args * ', '
      end

      def log(sql, args, name, &block)
        super(expand(sql, args), name, &block)
      end

      def select_all(sql, name = nil, format = :hash) # :nodoc:
        translate(sql) do |sql, args|
          log(sql, args, name) do
            @connection.query(format, sql, *args)
          end
        end
      end

      def select_one(sql, name = nil, format = :hash) # :nodoc:
        translate(sql) do |sql, args|
          log(sql, args, name) do
            @connection.query(format, sql, *args).first
          end
        end
      end

      def execute(sql, name = nil, &block) # :nodoc:
        translate(sql) do |sql, args|
          log(sql, args, name) do
            @connection.execute(sql, *args, &block)
          end
        end
      end

      def insert(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil) # :nodoc:
        execute(sql, name)
        id_value
      end

      alias_method :update, :execute
      alias_method :delete, :execute

      def begin_db_transaction() # :nodoc:
        @transaction = @connection.transaction
      end

      def commit_db_transaction() # :nodoc:
        @transaction = @connection.commit
      end

      def rollback_db_transaction() # :nodoc:
        @transaction = @connection.rollback
      end

      def add_lock!(sql, options) # :nodoc:
        sql
      end

      def add_limit_offset!(sql, options) # :nodoc:
        if options[:limit]
          limit_string = "FIRST #{options[:limit]}"
          limit_string << " SKIP #{options[:offset]}" if options[:offset]
          sql.sub!(/\A(\s*SELECT\s)/i, '\&' + limit_string + ' ')
        end
      end

      # Returns the next sequence value from a sequence generator. Not generally
      # called directly; used by ActiveRecord to get the next primary key value
      # when inserting a new database record (see #prefetch_primary_key?).
      def next_sequence_value(sequence_name)
        select_one("SELECT GEN_ID(#{sequence_name}, 1) FROM RDB$DATABASE", nil, :array).first
      end

      # SCHEMA STATEMENTS ========================================

      def columns(table_name, name = nil) # :nodoc:
        sql = <<-END_SQL
          SELECT r.rdb$field_name, r.rdb$field_source, f.rdb$field_type, f.rdb$field_sub_type,
                 f.rdb$field_length, f.rdb$field_precision, f.rdb$field_scale,
                 COALESCE(r.rdb$default_source, f.rdb$default_source) rdb$default_source,
                 COALESCE(r.rdb$null_flag, f.rdb$null_flag) rdb$null_flag
          FROM rdb$relation_fields r
          JOIN rdb$fields f ON r.rdb$field_source = f.rdb$field_name
          WHERE r.rdb$relation_name = '#{table_name.to_s.upcase}'
          ORDER BY r.rdb$field_position
        END_SQL
        select_all(sql, name, :array).collect do |field|
          field_values = field.collect do |value|
            case value
              when String         then value.rstrip
              else value
            end
          end
          FbColumn.new(*field_values)
        end
      end

      def tables(name = nil)
        @connection.table_names.map {|t| t.downcase }
      end

      def indexes(table_name, name = nil) #:nodoc:
        result = @connection.indexes.values.select {|ix| ix.table_name == table_name && ix.index_name !~ /^rdb\$/ }
        indexes = result.map {|ix| IndexDefinition.new(table_name, ix.index_name, ix.unique, ix.columns) }
        indexes
      end

      def table_alias_length
        255
      end

      def rename_column(table_name, column_name, new_column_name)
        execute "ALTER TABLE #{table_name} ALTER COLUMN #{column_name} TO #{new_column_name}"
      end

      def remove_index(table_name, options = {})
        execute "DROP INDEX #{quote_column_name(index_name(table_name, options))}"
      end

      def supports_migrations?
        false
      end

      def native_database_types
        {
          :primary_key => "integer not null primary key",
          :string      => { :name => "varchar", :limit => 255 },
          :text        => { :name => "blob sub_type text" },
          :integer     => { :name => "integer" },
          :float       => { :name => "float" },
          :datetime    => { :name => "timestamp" },
          :timestamp   => { :name => "timestamp" },
          :time        => { :name => "time" },
          :date        => { :name => "date" },
          :binary      => { :name => "blob" },
          :boolean     => { :name => "integer" }
        }
      end

      private
        # Maps uppercase Firebird column names to lowercase for ActiveRecord;
        # mixed-case columns retain their original case.
        def fb_to_ar_case(column_name)
          column_name =~ /[[:lower:]]/ ? column_name : column_name.downcase
        end

        # Maps lowercase ActiveRecord column names to uppercase for Fierbird;
        # mixed-case columns retain their original case.
        def ar_to_fb_case(column_name)
          column_name =~ /[[:upper:]]/ ? column_name : column_name.upcase
        end
    end
  end
end
