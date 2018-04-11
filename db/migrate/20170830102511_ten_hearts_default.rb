class TenHeartsDefault < ActiveRecord::Migration
  def up
    change_column_default :users, :grants, (ENV['DEFAULT_HEARTS'].to_f || 10)
  end

  def down
    change_column_default :users, :grants, 0
  end
end
