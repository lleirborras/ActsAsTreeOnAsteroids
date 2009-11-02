require File.dirname(__FILE__) + '/lib/active_record/acts/tree_on_asteroids.rb'

ActiveRecord::Base.send :include, ActiveRecord::Acts::TreeOnAsteroids
