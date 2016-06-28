# -*- encoding : utf-8 -*-
class Destination < ActiveRecord::Base

  has_many :rates
  has_many :flatrate_destinations, :dependent => :destroy
  has_many :calls, :finder_sql => 'SELECT * FROM calls WHERE prefix = \'#{prefix}\''
  belongs_to :destinationgroup
  belongs_to :direction, :foreign_key => 'direction_code', :primary_key => 'code'

  validates_uniqueness_of :prefix
  validates_presence_of :prefix, :subcode, :direction_code

  before_destroy :dest_before_destroy

  def dest_before_destroy
    th = Thread.new { @c=Call.find(:first, :select => 'id', :conditions => "prefix = '#{prefix}'") }

    if rates.size > 0
      errors.add(:rates, _("rates_exist") + ": " + prefix)
      return false
    end

    th.join
    if @c
      errors.add(:calls, _("calls_to_this_destination_exist") + ": " + prefix)
      return false
    end

  end

  def direction
    Direction.find(:first, :conditions => ["code = ?", self.direction_code], :order => " name ASC")
  end

  def calls
    Call.find(:all, :conditions => ["prefix = ?", prefix])
  end

  def sms_rates(tariff)
    SmsRate.find(:first, :conditions => ["prefix=? AND sms_tariff_id=?", prefix, tariff.id])
  end

  def Destination.auto_assignet_to_dg

    sql = "UPDATE destinations LEFT JOIN destinationgroups ON (destinationgroups.flag = destinations.direction_code ) SET destinations.destinationgroup_id =  destinationgroups.id WHERE destinations.destinationgroup_id = 0 AND destinations.direction_code != '' AND destinations.subcode = destinationgroups.desttype"
    res = ActiveRecord::Base.connection.execute(sql)
    sql2 = "UPDATE destinations LEFT JOIN destinationgroups ON (destinationgroups.flag = destinations.direction_code ) SET destinations.destinationgroup_id =  destinationgroups.id WHERE destinations.destinationgroup_id = 0 AND destinations.name LIKE '%MOB%' AND destinationgroups.desttype = 'MOB' AND destinations.direction_code != ''"
    res = ActiveRecord::Base.connection.execute(sql2)
    sql3 = "UPDATE destinations LEFT JOIN destinationgroups ON (destinationgroups.flag = destinations.direction_code ) SET destinations.destinationgroup_id =  destinationgroups.id WHERE destinations.destinationgroup_id = 0 AND destinations.name LIKE '%NGN%' AND destinationgroups.desttype = 'NGN' AND destinations.direction_code != ''"
    res = ActiveRecord::Base.connection.execute(sql3)
    sql4 = "UPDATE destinations LEFT JOIN destinationgroups ON (destinationgroups.flag = destinations.direction_code ) SET destinations.destinationgroup_id =  destinationgroups.id WHERE destinations.destinationgroup_id = 0 AND destinations.name LIKE '%FIX%' AND destinationgroups.desttype = 'FIX' AND destinations.direction_code != ''"
    res = ActiveRecord::Base.connection.execute(sql4)
    sql5 = "UPDATE destinations LEFT JOIN destinationgroups ON (destinationgroups.flag = destinations.direction_code ) SET destinations.destinationgroup_id =  destinationgroups.id WHERE destinations.destinationgroup_id = 0 AND destinations.direction_code != ''"
    res = ActiveRecord::Base.connection.execute(sql5)
  end

  def Destination.select_destination_assign_dg(page, order)
    limit = Confline.get_value("Items_Per_Page").to_i
    offset = limit*(page-1)

    sql = "SELECT * FROM (
            SELECT * FROM (
              SELECT * FROM (
                SELECT destinations.id, prefix, destinations.name, destinationgroups.id AS dgid, destinationgroups.name AS dgn, destinationgroups.desttype,  direction_code, 1 AS p FROM destinations
                  JOIN destinationgroups ON (flag = direction_code  )
                  WHERE destinationgroup_id = 0 AND ((destinations.name LIKE '%MOB%' AND desttype= 'MOB') OR ((destinations.name LIKE '%special%' OR destinations.name LIKE '%premium%') AND desttype= 'NGN') OR ((destinations.name LIKE '%proper%') AND desttype= 'FIX')) GROUP BY id ORDER BY direction_code  ) AS v1
              UNION
              SELECT * FROM (
                SELECT destinations.id, prefix, destinations.name, destinationgroups.id AS dgid, destinationgroups.name AS dgn, destinationgroups.desttype,  direction_code, 4 AS p FROM destinations
                  JOIN destinationgroups ON (flag = direction_code )
                  WHERE destinationgroup_id = 0 AND desttype = subcode GROUP BY id ORDER BY direction_code ) AS v2
              UNION
              SELECT * FROM (
                SELECT destinations.id, prefix, destinations.name, destinationgroups.id AS dgid, destinationgroups.name AS dgn, destinationgroups.desttype,  direction_code, 5 AS p FROM destinations
                  JOIN directions ON (directions.code = destinations.direction_code)
                  JOIN destinationgroups ON (flag = direction_code  )
                  WHERE destinationgroup_id = 0 AND  destinationgroups.name = directions.name GROUP BY id ORDER BY direction_code  ) AS v3
            ) AS v4 ORDER BY p ASC
          ) AS v5 GROUP BY id ORDER BY #{order}, id LIMIT #{limit} OFFSET #{offset}"


    destination = Destination.find_by_sql(sql)
    return destination
  end

  def find_rates_and_tariffs(user_id, user_tariff_id = '', callshop = 0)
    tariff_clause = user_tariff_id.present? ? ['tariffs.id = ?', user_tariff_id] : ''
    select_clause = 'rates.*, tariffs.name, tariffs.purpose, tariffs.owner_id, tariffs.currency, ' +
      ' IF(IFNULL(rates.effective_from, 0) = rates2.max_effective_from, 1, 0) AS active'
    manual_where_clause = '(rates.destination_id = ? OR rates.destinationgroup_id IN ' +
      '(SELECT destinationgroup_id FROM destinations WHERE id = ?))'

    if callshop.to_i > 0
      users_tariffs = User.includes(:usergroups).
                          where(['usergroups.group_id = ? AND usergroups.gusertype != "manager"',callshop]).
                          all.map(&:tariff_id).join(', ')
    else
      # If callshop not present retrieving Tariffs for owner
      users_tariffs = Tariff.where(['tariffs.owner_id = ?', user_id]).all.map(&:id).join(', ')
      where_clause = ['tariffs.owner_id = ?', user_id]
    end

    where_clause = users_tariffs.present? ? "rates.tariff_id IN (#{users_tariffs})" : ''

    if where_clause.present?
      Rate.select(select_clause)
          .joins('LEFT JOIN tariffs ON (tariffs.id = rates.tariff_id)')
          .joins('LEFT JOIN (SELECT rates.tariff_id, rates.destination_id, IFNULL(MAX(rates.effective_from), 0) AS max_effective_from ' +
                 'FROM rates WHERE (rates.effective_from < now() OR rates.effective_from IS NULL) ' +
                 "AND rates.tariff_id IN (#{users_tariffs}) AND rates.destination_id = #{id} " +
                 'GROUP BY rates.tariff_id, rates.destination_id) ' +
                 'rates2 ON (rates2.tariff_id = rates.tariff_id AND rates.destination_id = rates2.destination_id)')
          .where([manual_where_clause, id, id])
          .where(where_clause)
          .where(tariff_clause)
          .order('tariffs.purpose ASC, rates.effective_from DESC').all
    else
      []  # Tariff Doesn't exists so Rates shouldn't exist for non existing tariff, no need to wase time with sql
    end
  end

=begin
  Renames all destination names that have certaint prefix pattern.

  *Params*
  name - destination name, may be blank. if logner than 255 symbols, name will be truncated
  prefix - prefix pattern. Hybrid of mysql's REGEXP and LIKE
=end
  def self.rename_by_prefix(name, prefix)
    update = "name = ?", name.to_s
    condition = prefix_pattern_condition(prefix)
    Destination.update_all(update, condition)
  end

=begin
  Finds all destinations that match supplied prefix pattern

  *Params*
  prefix - prefix pattern. Hybrid of mysql's REGEXP and LIKE

  *Returns*
  destinations - array containing all found destinations
=end
  def self.dst_by_prefix(prefix)
    condition = prefix_pattern_condition(prefix)
    find(:all, :conditions => condition, :include => :destinationgroup)
  end

=begin
  *Params*
  prefix - prefix pattern. Hybrid of mysql's REGEXP and LIKE

  *Returns*
  condition - condition with regular expression
=end
  def self.prefix_pattern_condition(prefix)
    condition = "prefix REGEXP ?", prefix_pattern(prefix)
  end

=begin
  Deletes % if it is supplied in pattern, because this is not a metacharacter
  of regexp and supplied pattern is hybrid of mysql's REGXEP and LIKE.
  if you would pass prefix X, search would look for pattern Y:
  12%3 -> ^123(thats a system wide feature, heck knows why. AJ)
  123% -> ^123
  %123 -> ^123(thats a system wide feature, heck knows why. AJ)
  123  -> ^123$
=end
  def self.prefix_pattern(prefix)
    '^' + (prefix.to_s.include?('%') ? prefix.to_s.delete("%") : prefix.to_s + '$')
  end
end
