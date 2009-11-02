module ActiveRecord
  module Acts
    module TreeOnAsteroids
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Specify this +acts_as+ extension if you want to model a tree structure by providing a parent association and a children
      # association. This requires that you have a foreign key column, which by default is called +parent_id+.
      #
      #   class Category < ActiveRecord::Base
      #     acts_as_tree_on_asteroids :position => "name"
      #   end
      #
      #   Example:
      #   root
      #    \_ child1
      #         \_ subchild1
      #         \_ subchild2
      #
      #   root      = Category.create("name" => "root")
      #   child1    = root.children.create("name" => "child1")
      #   subchild1 = child1.children.create("name" => "subchild1")
      #
      #   root.parent   # => nil
      #   child1.parent # => root
      #   root.children # => [child1]
      #   root.children.first.children.first # => subchild1
      #
      # In addition to the parent and children associations, the following instance methods are added to the class
      # after calling <tt>acts_as_tree</tt>:
      # * <tt>siblings</tt> - Returns all the children of the parent, excluding the current node (<tt>[subchild2]</tt> when called on <tt>subchild1</tt>)
      # * <tt>self_and_siblings</tt> - Returns all the children of the parent, including the current node (<tt>[subchild1, subchild2]</tt> when called on <tt>subchild1</tt>)
      # * <tt>ancestors</tt> - Returns all the ancestors of the current node (<tt>[child1, root]</tt> when called on <tt>subchild2</tt>)
      # * <tt>root</tt> - Returns the root of the current node (<tt>root</tt> when called on <tt>subchild2</tt>)
      module ClassMethods
        # Configuration options are:
        #
        # * <tt>foreign_key</tt> - specifies the column name to use for tracking of the tree (default: +parent_id+)
        # * <tt>position</tt> - makes it possible to sort the children according to this SQL snippet.
        # * <tt>counter_cache</tt> - keeps a count in a +children_count+ column if set to +true+ (default: +false+).
        def acts_as_tree_on_asteroids(options = {})
          configuration = { :foreign_key => "parent_id", :position => "position", :counter_cache => nil }
          configuration.update(options) if options.is_a?(Hash)

          belongs_to :parent, :class_name => name, :foreign_key => configuration[:foreign_key], :counter_cache => configuration[:counter_cache]
          has_many :children, :class_name => name, :foreign_key => configuration[:foreign_key], :order => configuration[:position], :dependent => :destroy

          class_eval <<-EOV
            include ActiveRecord::Acts::TreeOnAsteroids::InstanceMethods

            default_scope :order => :#{configuration[:position]}

            before_validation :update_position
            before_save :auto_position

            validates_presence_of :#{configuration[:position]}
            validates_numericality_of :#{configuration[:position]}, :only_integer => true
            validates_numericality_of :#{configuration[:foreign_key]}, :only_integer => true, :allow_nil => true

            def self.roots
              find(:all, :conditions => "#{configuration[:foreign_key]} IS NULL", :order => #{configuration[:position].nil? ? "nil" : %Q{"#{configuration[:position]}"}})
            end

            def self.root
              find(:first, :conditions => "#{configuration[:foreign_key]} IS NULL", :order => #{configuration[:position].nil? ? "nil" : %Q{"#{configuration[:position]}"}})
            end

            def self.position=(i)
              @position = i
            end

            private
              def update_position
                self.position = (last_brother ? last_brother.position + 1 : 1) if self.position.nil? 
              end

              def auto_position
                if brothers(:conditions => {:position => position}) && id
                  original = self.class.find(id)
                  if original.position < position
                    brothers(:conditions => ["position <= ? && position > ?", position, original.position]).collect{|brother| brother.update_attributes :position => "position-1"}
                  else
                    brothers(:conditions => ["position > ? && position <= ?", position, original.position]).collect{|brother| brother.update_attributes :position => "position+1"}
                  end
                end
              end
            public
          EOV
        end
      end

      module InstanceMethods
        # Returns list of ancestors, starting from parent until root.
        #
        #   subchild1.ancestors # => [child1, root]
        def ancestors
          node, nodes = self, []
          nodes << node = node.parent while node.parent
          nodes
        end

        # Returns the root node of the tree.
        def root
          node = self
          node = node.parent while node.parent
          node
        end

        # Returns all siblings of the current node.
        #
        #   subchild1.siblings # => [subchild2]
        def siblings
          self_and_siblings - [self]
        end

        # Returns all siblings and a reference to the current node.
        #
        #   subchild1.self_and_siblings # => [subchild1, subchild2]
        def self_and_siblings
          parent ? parent.children : self.class.roots
        end

        # Returns true if the node has children, otherwise false
        def is_leaf?
          children.blank?
        end

        # Returns the first child, unless node is a leaf 
        def first_child
          children.first unless is_leaf?
        end

        # Returns the last child, unless node is a leaf 
        def last_child
          children.last unless is_leaf?
        end

        # Returns all brothers to this node
        def brothers(opts={})
          conditions = (id.nil? ? {} : {:conditions => ["id != ?", self.id]})
          parent ? parent.children.all(conditions) : self.class.find_all_by_parent_id(nil, conditions)
        end

        # Returns the first brother, unless node is a leaf 
        def first_brother(opts={})
          brothers(opts).first 
        end

        # Returns the last brother, unless node is a leaf 
        def last_brother(opts={})
          brothers(opts).last 
        end

        #Returns the level of the node at the tree
        def level
          l = 1
          p = parent
          while !p.nil?
            l += 1
            p = p.parent
          end
          l
        end
      end
    end
  end
end
