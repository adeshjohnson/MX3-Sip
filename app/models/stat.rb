# -*- encoding : utf-8 -*-
class Stat < ActiveRecord::Base
    
	attr_protected
	
	def self.find_rates_and_tariffs_by_number(user_id, id, phrase, user_tariff_id = '')
    tariff_clause = user_tariff_id.present? ? " AND tariffs.id = #{user_tariff_id}" : ''
    sql = 'SELECT * FROM (SELECT tariffs.name AS tariffs_name, tariffs.purpose, tariffs.currency, tariffs.id AS tariffs_id, ' +
          'ratedetails.start_time, ratedetails.end_time, ratedetails.rate, ' +
          'destinations.prefix, destinations.direction_code, destinations.subcode, destinations.name, ' +
          'aratedetails.price, aratedetails.start_time AS arate_start_time, aratedetails.end_time AS arate_end_time, ' +
          'rates.id AS rate_id, rates.effective_from AS effective_from, ' +
          'IF(IFNULL(rates.effective_from, 0) = rates2.max_effective_from, 1, 0) AS active, ' +
          'ratedetails.id AS ratedetails_id, aratedetails.daytype AS arate_daytype ' +
          'FROM rates ' +
          'LEFT OUTER JOIN tariffs ON tariffs.id = rates.tariff_id ' +
          'LEFT OUTER JOIN ratedetails ON ratedetails.rate_id = rates.id ' +
          'LEFT OUTER JOIN aratedetails ON aratedetails.rate_id = rates.id ' +
          'LEFT OUTER JOIN destinations ON ' +
          '(destinations.id = rates.destination_id OR destinations.destinationgroup_id = rates.destinationgroup_id) ' +
          "AND destinations.prefix IN (#{phrase.join(",")}) " +
          'LEFT JOIN ' +
           '(SELECT rates.tariff_id, rates.destination_id, ' +
           'IFNULL(MAX(rates.effective_from), 0) AS max_effective_from ' +
           'FROM rates ' +
           'WHERE (rates.effective_from < now() OR rates.effective_from IS NULL) ' +
           'GROUP BY rates.tariff_id, rates.destination_id) ' +
           'rates2 ON (rates2.tariff_id = rates.tariff_id AND rates.destination_id = rates2.destination_id) ' +
          'WHERE ( ' +
          "(rates.destination_id IN (#{id.join(",")}) OR rates.destinationgroup_id IN " +
          "(SELECT destinationgroup_id FROM destinations WHERE id IN (#{id.join(",")}))) " +
          "AND tariffs.owner_id = #{user_id}#{tariff_clause}) ORDER BY LENGTH(destinations.prefix) DESC) AS v " +
          'ORDER BY purpose ASC, effective_from DESC'
    ActiveRecord::Base.connection.select_all(sql)
	end
end
