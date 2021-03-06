#frozen_string_literal: true

# Basic class to communication with databese
class Database
  attr_accessor :config, :name

  def initialize(config)
    @config = config
    @fake_len = CONFIG['fake_datas']
    @timeout = CONFIG['database']['timeout']
    @timeout ||= 3600
    @db = Sequel.connect(
      adapter: :mysql2,
      database: @config['database']['name'],
      user: CONFIG['database']['user'],
      host: CONFIG['database']['host'],
      port: CONFIG['database']['port'],
      max_connections: CONFIG['database']['max_connections'],
      #single_threaded: :single_threaded,
      timeout: @timeout,
      write_timeout: @timeout,
      read_timeout: @timeout,
      connect_timeout: @timeout,
      pool_timeout: @timeout,
      password: CONFIG['database']['pass']
    )
    unless CONFIG['locale'].nil?
	Faker::Config.locale = CONFIG['locale']
    end
    unless CONFIG['bank_country_code'].nil?
	@bank_country_code = CONFIG['bank_country_code']
    end
    @db.extension(:connection_validator)
  end

  def anonymize
    insert_fake_data
    before_queries
    if @config['keys']
      @config['tables'].each do |table_name, columns_in_order|
        columns = columns_in_order.to_a.reverse.to_h
        key_name = get_key_name(table_name,columns)
        if  key_name[table_name] != nil
          counter   = @db.fetch(prepare_query(table_name, columns)).collect{|nb_entries| nb_entries[:sql_nb_entries]}[0]
          keys_list = @db.fetch(prepare_key_list(table_name, columns)).collect{|cle| cle[:sql_key_list]}
          ctr_keys_list=keys_list.length-1
          #queries = column_query(table_name, columns)
          if counter > ctr_keys_list+1
            puts "[OMG]The key column count is less than all rows count in the table"
          else
            @db.pool.connection_validation_timeout = -1
            @db.disconnect ## Disconnection to make a specific connection for MT Process           
            Parallel.map(0..ctr_keys_list,in_processes: (Concurrent.processor_count*2),progress: "Update table #{table_name} to inject fake data") do |i|
              key_in_list=escape_characters_in_string(keys_list[i])
#              @db.disconnect ## Disconnection to make a specific connection for MT Process           
              @db.transaction do
                @db[:"#{table_name}"].for_update.where(Sequel.lit("#{key_name[table_name]}=#{key_in_list}"))
                column_query_if_key(table_name, columns,key_name,key_in_list,i+1).each do |queri|       
                    @db.run queri
                end
              end
            end
          end
        else 
          queries = column_query(table_name, columns)
	  progressbar = ProgressBar.create(:title => "Updating #{table_name}")
          queries.each do |query|
            progressbar.increment
            @db.run query
          end
        end
      end
    else
      @config['tables'].each do |table_name, columns|
        queries = column_query(table_name, columns)
        queries.each do |query|
          @db.run query
        end
      end 
    end
    after_queries
    remove_fake_data
  end


  def prepare_query(table_name,columns)
    count_entries=""
    columns.each do |column_name, info|
      if info['key'] == '1'
        key_column=column_name;
        count_entries = "SELECT count(#{column_name}) as sql_nb_entries from #{table_name};"
        break
      end
    end
    count_entries
  end
  def get_key_name(table_name,columns)
    key_name=Hash.new()
    @config['tables'].each do |table_name, columns|
      columns.each do |column_name, info|
        if info['key'] == '1'
          key_name[table_name.to_s] = column_name.to_s
          break
        end
      end
    end
    key_name
  end
  def prepare_key_list(table_name,columns)
    key_list=""
    columns.each do |column_name, info|
      if info['key'] == '1'
        key_column=column_name;
        key_list = "SELECT #{column_name} as sql_key_list from #{table_name} WHERE #{column_name} IS NOT NULL;"
        break
      end
    end
    key_list
  end
  def column_query_if_key(table_name, columns,key_name,keys_for_where,id)
    queries = []

    columns.each do |column_name, info|
      Object.const_get("Database::#{translate_acton_to_class_name(info['action'])}").select_for_update(table_name, column_name, info,key_name,keys_for_where,id).each do |query|
        queries.push query
      end
      break if info['action'] == 'truncate'
    end

    queries
  end



  def column_query(table_name, columns)
    queries = []

    columns.each do |column_name, info|
      Object.const_get("Database::#{translate_acton_to_class_name(info['action'])}").query(table_name, column_name, info).each do |query|
        queries.push query
      end
      break if info['action'] == 'truncate'
    end

    queries
  end

  def before_queries
    if @config['custom_queries'] &&
        @config['custom_queries']['before'] &&
        @config['custom_queries']['before'].is_a?(Array)
        @db.disconnect
        Parallel.each(@config['custom_queries']['before'],in_processes: (Concurrent.processor_count*2),progress: "Executing thoses queries #{@config['custom_queries']['before']}") do |query|
    	    @db.run "SET FOREIGN_KEY_CHECKS=0;"
	        @db.run query
    	    @db.run "SET FOREIGN_KEY_CHECKS=1;"
      end
    end
  end

  def after_queries
    if @config['custom_queries'] &&
        @config['custom_queries']['after'] &&
        @config['custom_queries']['after'].is_a?(Array)

      @config['custom_queries']['after'].each do |query|
        @db.run query
      end
    end
  end

  def insert_fake_data
    Fake.create_fake_user_table @db
    unless @config['birthday'].nil?
	@min_age = @config['birthday']['min_age']
	@max_age = @config['birthday']['max_age']
    else
	@min_age = 18
	@max_age = 65
    end

    fake_user = @db[:fake_user]
    @db.pool.connection_validation_timeout = -1
    @db.disconnect ## Disconnection to make a specific connection for MT Process
    Parallel.map(1..@fake_len,in_processes: (Concurrent.processor_count*2),progress: "Making fake data table") {
      fake_user.insert(Fake.user_bank(@bank_country_code,@min_age,@max_age))
    }
    @db.disconnect ## Disconnection to make a specific connection for MT Process
  end

  def remove_fake_data
    @db.drop_table :fake_user
  end

  # rubocop:disable Metrics/MethodLength
  def translate_acton_to_class_name(action)
    case action
    when 'truncate'
      class_name = 'Truncate'
    when 'empty', 'set_static'
      class_name = 'Static'
    when 'eav_update'
      class_name = 'Eav'
    when 'json_update'
      class_name = 'Json'
    when 'multiple_update'
      class_name = 'Multiple'
    else
      class_name = 'Column'
    end

    class_name
  end
  # rubocop:enable Metrics/MethodLength

  def self.prepare_select_for_query(type)
      query = "SELECT fake_user.#{type} "
    query
  end
  def escape_characters_in_string(string)
    if string.is_a? String
      pattern = /(\'|\"|\.|\*|\/|\-|\\|\)|\$|\+|\(|\^|\?|\!|\~|\`)/
      string.gsub(pattern){|match|"\\"  + match}
    elsif string.is_a? Integer
       string=string.to_s
       string.gsub(/\s+/, "")
    end
  end
end

