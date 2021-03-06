# -*- encoding : utf-8 -*-
class Payment < ActiveRecord::Base
  belongs_to :user, :include => [:tax]
  belongs_to :provider
  has_many :cc_invoices

  after_create { |record| Action.add_action_hash(User.current, {:action => record.paymenttype.to_s == 'manual' ? 'manual_payment_created' : 'card_payment_created', :data => record.user_id, :data2 => record.amount, :data3 => record.currency, :target_id => record.id, :target_type => 'Payment'}) if record.paymenttype.to_s == 'manual' or record.paymenttype.to_s == 'Card' }

  after_destroy { |record| Action.add_action_hash(User.current, {:action=>'manual_payment_deleted', :data=>record.user_id, :data2=>record.amount, :data3=>record.currency, :target_id=>record.id, :target_type=>'Payment'}) if record.paymenttype.to_s == 'manual' }


  def invoice
    Invoice.find(:first, :conditions => ["invoices.payment_id = ?", self.id])
  end

  def voucher
    Voucher.find(:first, :include => [:tax], :conditions => ["vouchers.payment_id = ?", self.id])
  end

  def amount_in_currency(curr)
    self.amount / count_exchange_rate(curr, self.currency)
  end


  def count_exchange_rate(curr1, curr2)
    if curr1 != curr2
      return Currency.count_exchange_rate(curr1, curr2)
    else
      return 1
    end
  end

  def cards
    Card.find(:all, :conditions => ["id = ?", self.user_id], :order => "#{self.number}")
  end

  def payment_amount
    user = self.user
    pa = self.amount
    if self.paymenttype == "manual" and user
      pa = self.tax ? self.amount.to_d - self.tax.to_d : user.get_tax.count_amount_without_tax(self.amount.to_d)
    end
    pa = self.gross if ["webmoney", "cyberplat", "linkpoint", "voucher", "ouroboros", "subscription", "paypal", "paypal_fee"].include?(self.paymenttype.to_s)
    pa = self.amount if ["invoice"].include?(self.paymenttype.to_s)
    pa
  end

  def payment_amount_with_vat(nice_number_digits)
    if self.tax && !["webmoney", "cyberplat", "linkpoint", "voucher", "ouroboros", "subscription", "invoice", "paypal", 'manual'].include?(self.paymenttype)
      return self.amount.to_f + self.tax.to_f
    else
      if self.paymenttype == "invoice" and self.invoice
        return self.invoice.price_with_tax
      else
        return self.amount
      end
    end
  end

  def amount_to_system_currency
    self.amount * Currency.count_exchange_rate(self.currency, Currency.get_default)
  end

  def Payment.create_cards_action(order)

    if not payment = Payment.find(:first, :conditions => ["transaction_id = ?", order.transaction_id])
      payment = Payment.new
    end
    payment.shipped_at = order.shipped_at
    payment.completed = order.completed
    payment.paymenttype = 'paypal'
    payment.currency = order.currency
    payment.fee = order.fee
    payment.amount = order.amount
    payment.gross = order.gross.to_d
    payment.transaction_id = order.transaction_id
    payment.first_name = order.first_name
    payment.last_name = order.last_name
    payment.payer_email = order.payer_email
    payment.residence_country = order.residence_country
    payment.payer_status = order.payer_status
    payment.tax = order.tax
    payment.date_added = Time.now if not payment.date_added
    payment.save
    payment
  end

  def Payment.subscription_payment(user, amount)
    amount = amount.to_d * -1
    if amount != 0
      taxw = user.get_tax
      currency = Currency.get_default
      payment = Payment.new(
          :paymenttype => "subscription",
          :amount => user.get_tax.apply_tax(amount),
          :shipped_at => Time.now,
          :date_added => Time.now,
          :completed => 1,
          :gross => amount,
          :tax => user.get_tax.count_tax_amount(amount),
          :user_id => user.id,
          :first_name => user.first_name,
          :last_name => user.last_name)
      payment.currency = currency.name if currency
      payment.email = user.address.email if user.address
      return payment.save
    else
      return false
    end
  end

  def Payment.add_for_card(card, amount, currency = nil, owner_id = nil, description='')
    Payment.add_global({:paymenttype=>'Card', :tax => card.cardgroup.get_tax.count_tax_amount(amount), :currency => currency ? currency : card.cardgroup.tell_balance_in_currency, :user_id=>card.id, :card=>1, :amount=>amount, :owner_id => owner_id ? owner_id : card.cardgroup.owner_id, :description=>description})
  end

  def Payment.add_global(details= {})
    Payment.create({:shipped_at=>Time.now, :date_added=>Time.now, :completed=>1,:currency=>Currency.get_default}.merge(details))
  end

  def Payment.create_for_user(user, params = {})
    user = User.find(:first, :conditions => ["users.id = ?", user]) if user.class == Fixnum
    if user
      return Payment.new({
                             :user_id => user.id,
                             :first_name => user.first_name,
                             :last_name => user.last_name,
                             :date_added => Time.now(),
                             :owner_id => user.owner.id
                         }.merge(params))
    else
      return false
    end
  end

  def paypal_refund_payment(notify, user)
    # create new reverse payment
    MorLog.my_debug('Paypal reverse', true)
    refund_payment = self.dup
    refund_payment.fee = notify.fee.to_d
    refund_payment.amount = notify.gross.to_d
    refund_payment.gross = notify.gross.to_d - notify.tax.to_d
    refund_payment.tax = notify.tax.to_d
    refund_payment.currency = notify.currency.to_s
    refund_payment.transaction_id = notify.transaction_id.to_s
    refund_payment.first_name = notify.first_name.to_s
    refund_payment.last_name = notify.last_name.to_s
    refund_payment.payer_email = notify.payer_email.to_s
    refund_payment.residence_country = notify.residence_country.to_s
    refund_payment.payer_status = notify.payer_status.to_s
    refund_payment.date_added = Time.now
    refund_payment.pending_reason = notify.pending_reason.to_s
    refund_payment.pending_reason = "Denied" if notify.status == "Denied"
    refund_payment.pending_reason = "Reversed" if notify.reversed?
    refund_payment.paymenttype = "paypal_reversed"
    refund_payment.save
    if completed.to_i == 0
      # payment_1 is not addet to user balance , preverse_paymnet is not subtracted
      MorLog.my_debug("Payment #{refund_payment.id} is not reversed, becouse Paypal payment #{id} is not completed ", true)
      Action.add_action_hash(user, {:action => "Paypal Reverse Failed", :data => "Payment #{id} is not confirmed by admin", :data2 => id, :data3 => refund_payment.id})
    else
      # payment_1 is addet to user balance , subtracte reverse amount
      refund_payment.completed = 1
      user.balance += sprintf("%.2f", refund_payment.gross * Currency.count_exchange_rate(refund_payment.currency, Currency.find(1).name)).to_d
      if refund_payment.fee.to_d != 0.0 and Confline.get_value("PayPal_User_Pays_Transfer_Fee", 0).to_i == 1
        user.balance -= sprintf("%.2f", refund_payment.fee * Currency.count_exchange_rate(refund_payment.currency, Currency.find(1).name)).to_d
        fee_payment = refund_payment.dup
        fee_payment.paymenttype = "paypal_reversed_fee"
        fee_payment.fee = 0
        fee_payment.shipped_at = Time.now
        fee_payment.tax = 0
        fee_payment.completed = 1
        fee_payment.pending_reason = "Completed"
        fee_payment.amount = refund_payment.fee*-1
        fee_payment.gross = refund_payment.fee*-1
        fee_payment.save
        Action.add_action_hash(user, {:action => "Paypal Reverse", :data => "Payment #{id} is reversed, #{refund_payment.gross}", :data2 => id, :data3 => refund_payment.id})
      end
      user.save
      refund_payment.save
    end
  end

=begin
  Destroy single credit note associated with payment
=end
  def destroy_credit_note
    note = CreditNote.find(:first, :conditions => ["payment_id = #{self.id}"])
    if note
      note.destroy
    end
  end

=begin
  All payments for finacial data. excluding payment that are generated for calling cards.

  *Params*
  +owner_id+ owner of users that the user is interested in, but might be nil if 
     current user if ordinary user
  +user_id+ user that has invoices generated for him, might be nil if admin, 
     reseller or accountatn is not interested i certain user, but interested in all his users.
     BUT IF we are generating financial statemens for ordinary users, they cannot see other users
     information and must supply theyr own id
  +status+ valid status parameter would be 'paid' 'unpaid' or 'all', might be nil
     in that case all statuses would be selected
  +from_date, till_date+ dates as strings
  +ordinary_user+ if user is of type 'user' there is no need to join users table, but user_id mus
     be specified.
  +currency_name+ since payments may be in any currency, one must specify currency name that he
     wants payment prices to be represented.

  *Returns*
  +array of MockPayment instances+
=end
  def self.financial_statements(owner_id, user_id, status, from_date, till_date, ordinary_user, currency_name)
    condition = ['payments.card = 0']
    condition << ["payments.date_added BETWEEN '#{from_date} 00:00:00' AND '#{till_date} 23:59:59'"]
    if not ordinary_user
      condition << "payments.owner_id = #{owner_id}"
    end
    condition << "payments.user_id = #{user_id}" if user_id and user_id != 'all'
    if status != 'all' and ['paid', 'unpaid'].include? status
      condition << "payments.completed = #{status == 'paid' ? 1 : 0}"
    end

    return recalculate_payments(Payment.find(:all, :include => :user, :conditions => condition.join(" AND\n")), currency_name)
  end


=begin
  Since to callculate payment price, price with taxes and to convert it to users currency
  we need every payment and can not group it so that database server would just sum up prices, 
  like we did with credit notes or invoices. this is the method to do everyting:
  1. count price of payment in specified currency
  2. count price with tax in specified currency
  3. group all payments by theyr status
  4. sum it all up
  5. return information about all paid and unpaid payments.

  *Params* 
  +payments+ iterable of payment instances
 
  *Return*
  +array of payment data+ information about paid and unpaid payments
=end
  def self.recalculate_payments(payments, currency_name)
    Struct.new('MockPayment', :count, :price, :price_with_vat, :status)
    paid = Struct::MockPayment.new(0, 0, 0, 'paid')
    unpaid = Struct::MockPayment.new(0, 0, 0, 'unpaid')
    for payment in payments
      exchange_rate = Currency.count_exchange_rate(payment.currency, currency_name)
      price = Currency.count_exchange_prices({:exrate => exchange_rate, :prices => [payment.payment_amount.to_d]})
      price_with_vat = Currency.count_exchange_prices({:exrate => exchange_rate, :prices => [payment.payment_amount_with_vat(0)]})
      if payment.completed != 0
        paid.count += 1
        paid.price += price
        paid.price_with_vat += price_with_vat
      else
        unpaid.count += 1
        unpaid.price += price
        unpaid.price_with_vat += price_with_vat
      end
    end
    return paid, unpaid
  end

end
