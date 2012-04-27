class CreateDynamicAttributes < ActiveRecord::Migration
  def self.up
    create_table :dynamic_attributes do |t|
      t.string :target_type
      t.integer :target_id
      t.string :key
      t.string :value

      t.timestamps
    end
  end

  def self.down
    drop_table :dynamic_attributes
  end
end
