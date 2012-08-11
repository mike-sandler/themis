# SpecModule tracks class names created via SpecModel method for next cleanup.
module SpecModel
  def self.cleanup!
    ObjectSpace.each_object(SpecModel) do |klass|
      if Object.const_defined? klass.name.to_sym
        conn, table_name = klass.connection, klass.table_name
        conn.drop_table(table_name) if conn.tables.include?(table_name)
        Object.send :remove_const, klass.name.to_sym
      end
    end
    ActiveSupport::Dependencies::Reference.clear!
  end
end

# Creates an anonymous class, inherited from AR::Base. When inherited itself,
# creates a table based on passed parameters.
#  Example:
#    class Foo < SpecModel(:name => :string)
#      has_many :bars
#    end
#    class Bar < SpecModel(:foo_id => :integer, :amount => :float)
#      belongs_to :foo
#    end
#    ....
#    SpecModel.cleanup!
def SpecModel column_definition
  Class.new(ActiveRecord::Base) do
    self.abstract_class = true

    singleton_class.class_eval do
      alias_method :orig_inherited, :inherited
      define_method :inherited do |base|
        base.extend SpecModel
        orig_inherited base

        table_name = base.table_name
        conn = base.connection
        unless conn.tables.include? table_name
          conn.create_table(table_name) do |t|
            column_definition.each do |name, type|
              options = {}
              if type.to_s =~ /^(.+)!$/
                type = $1.to_sym
                options[:null] = false
              end
              options[:default] = 0 if name == :lock_version
              args = [type, name]
              args << options unless options.empty?
              t.send(*args)
            end
          end
        end
        base.reset_column_information
      end
    end
  end
end
