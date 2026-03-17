class CreateItems < ActiveRecord::Migration[7.2]
  def change
    create_table :items, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.string :item_type
      t.string :name
      t.text   :content
      t.string :folder, default: ''

      t.timestamps
    end
  end
end
