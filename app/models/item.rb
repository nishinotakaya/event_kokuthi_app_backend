class Item < ApplicationRecord
  self.primary_key = 'id'

  validates :name, presence: true
  validates :item_type, inclusion: { in: %w[event student] }

  before_create :set_custom_id

  private

  def set_custom_id
    prefix = item_type == 'event' ? 'event_' : 'student_'
    nums = Item.where(item_type: item_type)
                .map { |i| i.id.to_s.sub(prefix, '').to_i }
                .select { |n| n > 0 }
    self.id = "#{prefix}#{((nums.max || 0) + 1).to_s.rjust(3, '0')}"
  end
end
