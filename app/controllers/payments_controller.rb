# -*- encoding : utf-8 -*-
class PaymentsController < ApplicationController

  require "digest"
  require "mercadopago"

  layout "callc"
  skip_before_filter :verify_authenticity_token, :only => [:paypal_ipn]
  before_filter :check_post_method, :only => [:destroy, :create, :update]
  before_filter :check_localization, :except => [:paypal_ipn, :safetypay_ipn, :mercadopago_ipnn, :webmoney_result, :cyberplat_result, :ouroboros_accept, :linkpoint_ipn]
  before_filter :authorize, :except => [:paypal_ipn,  :safetypay_ipn, :mercadopago_ipnn, :webmoney_result, :cyberplat_result, :ouroboros_accept, :linkpoint_ipn]
  before_filter :check_if_can_see_finances, :only => [:index, :list, :payments_csv, :show, :new, :create, :update, :destroy]
  before_filter :find_user_session, :only => [:paypal, :paypal_pay, :personal_payments, :ouroboros, :ouroboros_pay, :safetypay, :safetypay_pay, :webmoney, :webmoney_pay, :cyberplat, :cyberplat_pay, :linkpoint_pay, :confirm_payment, :mercadopago, :mercadopago_pay]
  before_filter :find_payment, :only => [:confirm_payment, :change_description]

  @@payments_view = [:list, :payments_csv]
  @@payments_edit = [:manual_payment, :manual_payment_status]
  before_filter(:only => @@payments_view+@@payments_edit) { |c|
    allow_read, allow_edit = c.check_read_write_permission(@@payments_view, @@payments_edit, {:role => "accountant", :right => :acc_payments_manage, :ignore => true})
    c.instance_variable_set :@allow_read, allow_read
    c.instance_variable_set :@allow_edit, allow_edit
    true
  }

  def index
    redirect_to :action => :list and return false
  end

  def list
    @page_title = _('Payments')
    @page_icon = "creditcards.png"

    change_date

    session[:payments_list_c] ? @options = session[:payments_list_c] : @options = {}
    [:s_transaction, :s_completed, :s_username, :s_first_name, :s_last_name, :s_paymenttype, :s_amount_min, :s_amount_max, :s_currency, :s_number, :s_pin].each { |key|
      if params[:clear].to_i == 1
        @options[key] = ""
      else
        params[key] ? @options[key] = params[key].to_s : (@options[key] = "" if !@options[key])
      end
    }

    hide_uncompleted_payment = Confline.get_value("Hide_non_completed_payments_for_user", 0).to_i

    cond = ["date_added BETWEEN ? AND ?"]
    cond << "payments.owner_id = ?"
    cond_param = [q(session_from_datetime), q(session_till_datetime), correct_owner_id]

    if hide_uncompleted_payment == 1
      cond << " (payments.pending_reason != 'Unnotified payment' or payments.pending_reason is null)"
    end

    ["username", "first_name", "last_name"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s+"%", "users.#{col} LIKE ?", cond, cond_param) }

    ["number", "pin"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s+"%", "cards.#{col} LIKE ?", cond, cond_param) }

    ["paymenttype", "currency", "completed"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s, "payments.#{col} = ?", cond, cond_param) }

    ["transaction"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s+"%", "payments.transaction_id LIKE ?", cond, cond_param) }

    cond << "amount >= '#{current_user.to_system_currency(q(@options[:s_amount_min]))}' " if !@options[:s_amount_min].blank?
    cond << "amount <= '#{current_user.to_system_currency(q(@options[:s_amount_max]))}' " if !@options[:s_amount_max].blank?

    @payments = Payment.select("payments.*, payments.user_id as 'user_id', payments.first_name as 'payer_first_name', payments.last_name as 'payer_last_name', users.username, users.first_name, users.last_name, cards.number, cards.pin, cards.id as card_id",).where([cond.join(" AND ")] + cond_param).joins("left join users on (payments.user_id = users.id and payments.card = '0') left join cards on (payments.user_id = cards.id and payments.card != '0')   left join cardgroups on (cards.cardgroup_id = cardgroups.id)")

    @search = 1

    sql = "SELECT DISTINCT SUBSTRING(date_added,1,10) as 'pdate' FROM payments ORDER BY SUBSTRING(date_added,1,10) ASC"
    @payment_dates = ActiveRecord::Base.connection.select_all(sql)

    sql = "SELECT DISTINCT paymenttype as 'ptype' FROM payments ORDER BY paymenttype ASC"
    @payment_types = ActiveRecord::Base.connection.select_all(sql)

    sql = "SELECT DISTINCT currency as 'pcurr' FROM payments ORDER BY currency ASC"
    @payment_currencies = ActiveRecord::Base.connection.select_all(sql)

    @page = 1
    @page = params[:page].to_i if params[:page] and params[:page].to_i > 0

    @total_pages = (@payments.size.to_d / session[:items_per_page].to_d).ceil
    @page = @total_pages if params[:page].to_i > @total_pages
    @all_payments = @payments
    @payments= []

    iend = ((session[:items_per_page].to_i * @page) - 1)
    iend = @all_payments.size - 1 if iend > (@all_payments.size - 1)
    for i in ((@page - 1) * session[:items_per_page].to_i)..iend
      @payments << @all_payments[i] if !@all_payments[i].blank?
    end

    @total_amaunt= 0.to_d
    @total_amaunt_completed = 0.to_d
    @total_fee= 0.to_d
    @total_fee_completed= 0.to_d
    @total_amaunt_with_vat= 0.to_d
    @total_amaunt_with_vat_completed= 0.to_d

    for payment in @payments
      pa = payment.payment_amount
      #      if payment.paymenttype == "paypal" or payment.paymenttype == "manual"
      #        user = payment.user
      #        if user
      #          #tax = user.get_tax
      #          pa = payment.payment_amount if payment.paymenttype == "manual"
      #          #pa = tax.apply_tax(payment.gross) if payment.paymenttype == "paypal"
      #          pa = payment.payment_amount if payment.paymenttype == "paypal"
      #        end
      #      end
      #      pa = payment.gross if ["webmoney", "cyberplat",  "linkpoint", "voucher", "ouroboros", "subscription"].include?(payment.paymenttype.to_s)
      #      pa = payment.amount if payment.paymenttype == "invoice"
      @total_amaunt += get_price_exchange(pa, payment.currency)
      @total_fee += get_price_exchange(payment.fee, payment.currency)
      digits = (payment.paymenttype == "invoice" and payment.invoice) ? nice_invoice_number_digits(payment.invoice.invoice_type) : 0
      awv = payment.payment_amount_with_vat(digits)
      @total_amaunt_with_vat += get_price_exchange(awv, payment.currency)
      #Ticket 3421
      if payment.completed.to_i != 0
        @total_amaunt_completed += get_price_exchange(pa, payment.currency)
        @total_fee_completed += get_price_exchange(payment.fee, payment.currency)
        @total_amaunt_with_vat_completed += get_price_exchange(awv, payment.currency)
      end
    end

    session[:payments_list_c] = @options
    store_location
  end

  def payments_csv
    change_date

    session[:payments_list_c] ? @options = session[:payments_list_c] : @options = {}
    [:s_completed, :s_username, :s_first_name, :s_last_name, :s_paymenttype, :s_amount_min, :s_amount_max, :s_currency, :s_number, :s_pin].each { |key|
      params[key] ? @options[key] = params[key].to_s : (@options[key] = "" if !@options[key])
    }

    cond = ["date_added BETWEEN ? AND ?"]
    cond << "payments.owner_id = ?"
    cond_param = [q(session_from_datetime), q(session_till_datetime), correct_owner_id]

    ["username", "first_name", "last_name"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s+"%", "users.#{col} LIKE ?", cond, cond_param) }

    ["number", "pin"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s+"%", "cards.#{col} LIKE ?", cond, cond_param) }

    ["paymenttype", "currency", "completed"].each { |col|
      add_contition_and_param(@options["s_#{col}".to_sym], @options["s_#{col}".intern].to_s, "payments.#{col} = ?", cond, cond_param) }

    cond << "amount >= '#{q(@options[:s_amount_min])}' " if !@options[:s_amount_min].blank?
    cond << "amount <= '#{q(@options[:s_amount_max])}' " if !@options[:s_amount_max].blank?

    payments = Payment.find(:all,
                            :select => "payments.*, payments.user_id as 'user_id', users.username, users.first_name, users.last_name, cards.number, cards.pin, cards.id as card_id",
                            :joins => "left join users on (payments.user_id = users.id and payments.card = '0') left join cards on (payments.user_id = cards.id and payments.card != '0')   left join cardgroups on (cards.cardgroup_id = cardgroups.id)",
                            :conditions => [cond.join(" AND ")] + cond_param)

    sep = Confline.get_value("CSV_Separator", 0).to_s
    dec = Confline.get_value("CSV_Decimal", 0).to_s

    csv_string = "#{_('User')}/#{_('Card')}#{sep}#{_('Date')}#{sep}#{_('Confirm_date')}#{sep}#{_('Type')}#{sep}#{_('Amount')}#{sep}#{_('Fee')}#{sep}#{_('Amount_with_VAT')}#{sep}#{_('Currency')}#{sep}#{_('Completed')}*\n"

    total_amaunt= 0.to_d
    total_fee= 0.to_d
    total_amaunt_with_vat= 0.to_d

    for payment in payments

      if payment.card == 0
        name = nice_user(payment)
      else
        name = payment.number
      end

      tag = ""

      if payment.paymenttype.to_s == "voucher" and voucher = payment.voucher
        tag = " (" + voucher.tag.to_s + ")"
      end

      pa = payment.amount
      user = payment.user
      if (payment.paymenttype == "paypal" or payment.paymenttype == "manual") and user
        tax = user.get_tax
        pa = payment.payment_amount if payment.paymenttype == "manual"
        pa = tax.apply_tax(payment.amount) if payment.paymenttype == "paypal"
      end
      pa = payment.gross if payment.paymenttype == "webmoney" or payment.paymenttype == "cyberplat"

      digits = (payment.paymenttype == "invoice" and payment.invoice) ? nice_invoice_number_digits(payment.invoice.invoice_type) : 0
      awv = payment.payment_amount_with_vat(digits)

      completed = _('Yes')
      if  payment.completed.to_i == 0
        completed = _('No')
        completed += " (" + payment.pending_reason + ")" if payment.pending_reason
      end

      csv_string += "#{name.to_s}#{sep}#{nice_date_time payment.date_added}#{sep}#{nice_date_time payment.shipped_at}#{sep}#{payment.paymenttype.capitalize.to_s + tag.to_s}#{sep}#{pa.to_s.gsub(".", dec).to_s}#{sep}#{payment.fee.to_s.gsub(".", dec).to_s}#{sep}#{awv.to_s.gsub(".", dec).to_s}#{sep}#{payment.currency}#{sep}#{completed}\n"
      total_amaunt += get_price_exchange(pa, payment.currency)
      total_fee += get_price_exchange(payment.fee, payment.currency)
      total_amaunt_with_vat += get_price_exchange(awv, payment.currency)
    end

    dc = current_user.currency.name
    csv_string += "#{_('Total')}#{sep}#{sep}#{sep}#{sep}#{total_amaunt.to_s.gsub(".", dec).to_s}(#{dc})#{sep}#{total_fee.to_s.gsub(".", dec).to_s}(#{dc})#{sep}#{sep}#{total_amaunt_with_vat.to_s.gsub(".", dec).to_s}(#{dc })#{sep}#{sep}\n"
    filename = "Payments.csv"
    session[:payments_list_c] = @options
    if params[:test].to_i == 1
      render :text => "Payments_csv_is_ok\n\n"+csv_string
    else
      send_data(csv_string, :type => 'text/csv; charset=utf-8; header=present', :filename => filename)
    end

  end
  
   # Adesh. MercadoPago
  
  def mercadopago
    #@user in before filter
    @page_title = _('MercadoPago')
    @page_icon = "money.png"

    if session[:mercadopago_enabled].to_i == 0
      dont_be_so_smart
      redirect_to :controller => "callc", :action => "main" and return false
    end

    @mp_min_amount = Confline.get_value("MercadoPago_Min_Amount", @user.owner_id)
    @mp_max_amount = Confline.get_value("MercadoPago_Max_Amount", @user.owner_id)
	@mp_default_amount = Confline.get_value("MercadoPago_Default_Amount", @user.owner_id)

    @currency = Confline.get_value("MercadoPago_Default_Currency", @user.owner_id)
  end
  
  def mercadopago_pay
    #@user in before filter
    @page_title = _('MercadoPago')
    @page_icon = "money.png"

    if session[:mercadopago_enabled].to_i == 0
      dont_be_so_smart
      redirect_to :controller => "callc", :action => "main" and return false
    end
    #ticket 3698

    success_url = Web_URL + Web_Dir + "/payments/mercadopago_successss"
    pending_url = Web_URL + Web_Dir + "/payments/mercadopago_pendinggg"
    failure_url = Web_URL + Web_Dir + "/payments/mercadopago_failureee"
	
    mercadopago_ipn_url = Web_URL + Web_Dir + "/payments/mercadopago_ipnn"

    @amount = Confline.get_value("MercadoPago_Default_Amount", @user.owner_id).to_d
    @amount = params[:amount].to_d if params[:amount]

    mp_min_amount = Confline.get_value("MercadoPago_Min_Amount", @user.owner_id).to_d
    mp_max_amount = Confline.get_value("MercadoPago_Max_Amount", @user.owner_id).to_d

    @amount = mp_min_amount if mp_min_amount > 0.0 && @amount < mp_min_amount
    @amount = mp_max_amount if mp_max_amount > 0.0 && @amount > mp_max_amount

    @amount_with_vat = @user.get_tax.count_tax_amount(@amount) + @amount

    @currency = Confline.get_value("MercadoPago_Default_Currency", @user.owner_id).to_s
	client_id = Confline.get_value("MercadoPago_Client_id", @user.owner_id).to_s
	client_secret = Confline.get_value("MercadoPago_Client_secret", @user.owner_id).to_s
	test = Confline.get_value("MercadoPago_Test", @user.owner_id).to_i
	company = Confline.get_value("Company", @user.owner_id).to_s

	payment = Payment.new
	payment.paymenttype = 'MercadoPago'
	payment.amount = @amount_with_vat
	payment.currency = @currency
	payment.date_added = Time.now
	payment.completed = 0
	payment.gross = @amount
	payment.first_name = session[:first_name]
	payment.last_name = session[:last_name]
	payment.tax = @amount_with_vat - @amount
	payment.user_id = session[:user_id]
	payment.pending_reason = 'Unnotified payment'
	payment.owner_id = @user.owner_id
	payment.save
	payment_id = payment.id
	
	@mercadopago_url_token = mercadopago_token(client_id, client_secret, :payment_id => payment_id, :amount => @amount_with_vat, :currency => @currency, :success_url => success_url, :pending_url => pending_url, :failure_url => failure_url, :user_id => session[:user_id], :payer_name => @user.first_name.to_s, :payer_surname => @user.last_name.to_s, :payer_email => @user.email.to_s, :notification_url => mercadopago_ipn_url, :test => test, :marketplace => company)
	
	if @mercadopago_url_token.blank?
		flash[:notice] = _('MercadoPago_Error_Ocurred')
		redirect_to :controller => "callc", :action => "main" and return false	
	end
	
  end
  
  def mercadopago_successss
	flash[:status] = _('MercadoPago_Successful_Transaction')  #The operation was successful. Your balance will be updated automatically in few seconds/minutes.
	redirect_to :action => "personal_payments" and return false
  end
  
  def mercadopago_pendinggg
	flash[:notice] = _('MercadoPago_Pending_Transaction')
	redirect_to :action => "personal_payments" and return false
  end
  
  def mercadopago_failureee
	flash[:notice] = _('MercadoPago_Failed_Transaction')
	redirect_to :action => "personal_payments" and return false
  end
  
	def mercadopago_ipnn
		
		if Confline.get_value("MercadoPago_enabled").to_i == 0
			head :internal_server_error and return false
		end
		
		if  params[:topic].to_s == "merchant_order"
			head :ok and return false
		end
		
		if params[:topic].to_s != "payment" or params[:id].to_s ==""
			head :internal_server_error and return false
		end
		
		client_id = Confline.get_value("MercadoPago_Client_id").to_s
		client_secret = Confline.get_value("MercadoPago_Client_secret").to_s
		
		mp = MercadoPago.new(client_id, client_secret)
		if Confline.get_value("MercadoPago_Test").to_i == 1
			mp.sandbox_mode(true)
		end

		payment_info = mp.get_payment_info(params[:id])
		
		if (payment_info['status'] == "200")			
			if payment_info['response']['collection']['status'].to_s == "approved"			   
				# external_reference was send as payment_id*user_id to match payment
				reference = payment_info['response']['collection']['external_reference'].to_s
				reference = reference.partition("*")
				amount = payment_info['response']['collection']['total_paid_amount'].to_d
				currency = payment_info['response']['collection']['currency_id'].to_s
				# Validate/Match payment with internal info
				payment = Payment.find(:first, :conditions => ["id = ? AND paymenttype = 'MercadoPago' AND amount = ? AND currency = ? AND user_id = ?", reference.first.to_i, amount, currency, reference.last.to_i])
				if payment
				    if payment.completed == 1
						head :ok and return false
					end
					fee_percent = Confline.get_value("MercadoPago_Transfer_Fee_Percent").to_i
					fee = (amount - payment_info['response']['collection']['net_received_amount'].to_d)*(fee_percent.to_d/100)
					user = payment.user
					payment.fee = fee					
					payment.transaction_id = params[:id].to_s
					payment.date_added = Time.now if not payment.date_added
					payment.shipped_at = Time.now
					payment.pending_reason = payment_info['response']['collection']['status_detail'].to_s
					payment.completed = 1
					payment.payer_email = payment_info['response']['collection']['payer']['email'].to_s
					payment.first_name = payment_info['response']['collection']['payer']['first_name'].to_s
					payment.last_name = payment_info['response']['collection']['payer']['last_name'].to_s
					payment.description = payment_info['response']['collection']['payment_type'].to_s
					payment.save					
					user.balance += sprintf("%.2f", payment.gross * Currency.count_exchange_rate(payment.currency, Currency.find(1).name)).to_d
					if payment.fee.to_d != 0.0
						fee_payment = payment.dup
						fee_payment.paymenttype = "MercadoPago_Commission"									
						fee_payment.fee = 0
						fee_payment.amount =  payment.fee*(-1)
						fee_payment.gross = payment.fee*(-1)
						fee_payment.save
						user.balance -= sprintf("%.2f", payment.fee * Currency.count_exchange_rate(payment.currency, Currency.find(1).name)).to_d
					end
					user.save
          if !user.address.mob_phone.blank?
              #START ----- Send Notification by SMS
              @user1 = User.where(:id => 0).first
              message = _('Body_message_new_payment', payment.paymenttype.to_s, payment.amount.to_s, user.username.to_s, nice_number(user.balance.to_d).to_s)
              sms = SmsMessage.new
              sms.sending_date = Time.now
              sms.user_id = @user1.id
              sms.reseller_id = @user1.owner_id
              sms.number = user.address.mob_phone
              sms.sms_type = "payment"
              sms.reg_owner = user.owner_id
              sms.save
              if Confline.get_value("Send_fake_SMS_for_mobile_validation", user.owner_id).to_i == 0
                Thread.new {
                  sms.sms_send(@user1, @user1.sms_tariff, sms.number, @user1.sms_lcr, 1, message)
                }
              else
                sms.status_code = "7"
                sms.save
              end
              #END ----- Send Notification by SMS
          end		
					if !user.email.blank?
						User.current = user
						begin
							a = Thread.new {
							  send_email_to_user = EmailsController.send_user_email_after_payment(user, {:payment_amount => payment.amount, :payment_date => payment.shipped_at, :payment_fee => payment.fee, :payment_currency => payment.currency, :payment_type => payment.paymenttype})
							}
						rescue Exception => e
						  Action.add_action(user.id, "MercadoPago", "Email not sent to user #{user.username} after payment: #{payment.amount} #{payment.currency}")
						end
					else
						 Action.add_action(user.id, "MercadoPago", "User #{user.username} was not emailed after payment: #{payment.amount} #{payment.currency}. Email for is not registered.")
					end	
					Action.add_action(user.id, "MercadoPago", "Success Complete IPN")
					head :ok and return false	
				else
					head :internal_server_error and return false
				end			
			else
				head :ok and return false					
			end							
		end
		head :internal_server_error and return false
	end
  
  # Adesh. /MercadoPago

  ########## Linkpoint ##########################
  # added by A.Mazunin 16.04.2008               #
  # LinkpointCentral Payment System Integration #
  ###############################################

  def linkpoint
    @enabled = Confline.get_value("Linkpoint_Enabled", 0).to_i
    unless @enabled == 1
      render :text => "" and return false
    end
    @page_title = _('LinkPoint')
    @page_icon = "money.png"
    @currency = Confline.get_value("Linkpoint_Default_Currency")

  end

  def linkpoint_pay
    #@user in before filter
    unless Confline.get_value("Linkpoint_Enabled").to_i == 1
      render :text => "" and return false
    end

    Action.add_error(session[:user_id], "Linkpoint_user_URL_mismatches_WebURL", {:data2 => Web_URL + Web_Dir, :data3 => request.protocol + request.host}) unless check_request_url
    @page_title = _('LinkPoint')
    @page_icon = "money.png"
    @enabled = Confline.get_value("Linkpoint_Enabled", 0).to_i
    @linkpoint_ipn = Web_URL + Web_Dir + "/payments/linkpoint_ipn"
    @amount = Confline.get_value("Linkpoint_Default_Amount").to_d
    @amount = params[:amount].to_d if params[:amount]
    lp_min_amount = Confline.get_value("Linkpoint_Min_Amount").to_d
    @amount = lp_min_amount if @amount < lp_min_amount

    @amount_with_vat = @user.get_tax.count_tax_amount(@amount) + @amount

    @currency = Confline.get_value("Linkpoint_Default_Currency")
    @payment = Payment.new
    @payment.paymenttype = 'linkpoint'
    @payment.amount = @amount_with_vat
    @payment.currency = @currency
    @payment.date_added = Time.now
    @payment.completed = 0
    @payment.gross = @amount
    @payment.first_name = session[:first_name]
    @payment.last_name = session[:last_name]
    @payment.tax = @amount_with_vat - @amount
    @payment.user_id = session[:user_id]
    @payment.pending_reason = 'Unnotified payment'
    @payment.owner_id = @user.owner_id
    @payment.save
  end

  def linkpoint_ipn
    unless Confline.get_value("Linkpoint_Enabled").to_i == 1
      render :text => "" and return false
    end
    my_debug('linkpoint success accessed')
    @page_title = _('LinkPoint_Result')
    @page_icon = "money.png"
    @success = false
    if request.raw_post
      notify = Linkpoint::Notification.new(request.raw_post)
      @payment = Payment.where(["id = ?", notify.transaction_id]).first
      @test = Confline.get_value("Linkpoint_Test").to_i
      if request.protocol == "https://" or Confline.get_value("Linkpoint_Allow_HTTP").to_i == 1
        if notify.complete?
          if @payment
            if @payment.pending_reason == 'Unnotified payment'
              if @user = User.find(@payment.user_id)
                @success = true
                @payment.shipped_at = Time.now
                @payment.completed = 1
                @payment.pending_reason = 'Complete payment'
                @payment.transaction_id = ""
                @payment.user_id = @user.id
                @payment.date_added = Time.now if not @payment.date_added
                #@payment.residence_country = notify.country
                @payment.payment_hash = notify.approval_code
                @payment.save
                if @test == 0
                  @user.balance += sprintf("%.2f", (@payment.gross.to_d * Currency.count_exchange_rate(@payment.currency, Currency.find(1).name))).to_d
                  @user.save
                end

                MorLog.my_debug('Linkpoint: Success')
              else
                @reason = _("Internal_Error_Contact_Administrator")
                MorLog.my_debug('Linkpoint: User was not found')
                MorLog.my_debug("ID : #{@payment.user_id}")
              end
            else
              @reason = _("Internal_Error_Contact_Administrator")
              MorLog.my_debug('Linkpoint: Payment is invalid')
              MorLog.my_debug("Payment:   #{@payment.pending_reason}")
              MorLog.my_debug("Expected:  Unnotified payment")
            end
          else
            @reason = _("Internal_Error_Contact_Administrator")
            MorLog.my_debug('Linkpoint: Payment was not found')
            MorLog.my_debug("ID : #{notify.transaction_id}")
          end
        else
          @reason = _("Internal_Error_Contact_Administrator")
          MorLog.my_debug('Linkpoint: Transaction was not completed')
          MorLog.my_debug("Expected: APPROVED")
          MorLog.my_debug("Got:      #{notify.status}")
          if notify.status == "DECLINED"
            @payment.pending_reason = "Denied"
            @reason = _("Your_Payment_Was_Denied")
          end
          if notify.status == "FRAUD"
            @payment.pending_reason = ""
            @reason = _("Your_Payment_Was_Suspected_Of_Fraud")
          end
          @payment.save if @payment
        end
      else
        @reason = _("Unsecure_Transaction")
        MorLog.my_debug('Linkpoint: Unsecure access attempt. Suspected hack.')
        MorLog.my_debug("Payment:   '#{request.protocol}'")
        MorLog.my_debug("Expected:  'https://'")
      end
    else
      @reason = _("Empty_Response")
      MorLog.my_debug('Linkpoint: Empty response.')
    end
  end

  ############ PAYPAL ############

  def paypal
    #@user in before filter
    @page_title = _('PayPal')
    @page_icon = "money.png"

    if session[:paypal_enabled].to_i == 0
      dont_be_so_smart
      redirect_to :controller => "callc", :action => "main" and return false
    end

    @pp_min_amount = Confline.get_value("PayPal_Min_Amount", @user.owner_id)
    @pp_max_amount = Confline.get_value("PayPal_Max_Amount", @user.owner_id)

    @currency = Confline.get_value("Paypal_Default_Currency", @user.owner_id)
  end

  def paypal_pay
    #@user in before filter
    @page_title = _('PayPal')
    @page_icon = "money.png"

    if session[:paypal_enabled].to_i == 0
      dont_be_so_smart
      redirect_to :controller => "callc", :action => "main" and return false
    end
    #ticket 3698

    custom_redirect = Confline.get_value('PayPal_Custom_redirect', @user.owner_id).to_i
    custom_redirect_successful_payment = Confline.get_value('Paypal_return_url', @user.owner_id)
    custom_redirect_canceled_payment = Confline.get_value('Paypal_cancel_url', @user.owner_id)

    if custom_redirect and custom_redirect.to_i == 1
      @paypal_return_url = session[:url] + "/" + custom_redirect_successful_payment.to_s
      @paypal_cancel_url = session[:url] + "/" + custom_redirect_canceled_payment.to_s
    else
      @paypal_return_url = session[:url] + Web_Dir + "/payments/personal_payments"
      @paypal_cancel_url = session[:url] + Web_Dir + "/callc/main"
    end

    @paypal_ipn_url = session[:url] + Web_Dir + "/payments/paypal_ipn"

    @amount = Confline.get_value("PayPal_Default_Amount", @user.owner_id).to_d
    @amount = params[:amount].to_d if params[:amount]

    pp_min_amount = Confline.get_value("PayPal_Min_Amount", @user.owner_id).to_d
    pp_max_amount = Confline.get_value("PayPal_Max_Amount", @user.owner_id).to_d

    @amount = pp_min_amount if pp_min_amount > 0.0 && @amount < pp_min_amount
    @amount = pp_max_amount if pp_max_amount > 0.0 && @amount > pp_max_amount

    @amount_with_vat = @user.get_tax.count_tax_amount(@amount) + @amount

    #testing
    if Confline.get_value("PayPal_Test", @user.owner_id).to_i == 1
      @paypal_url = Paypal::Notification.test_ipn_url
    else
      @paypal_url = Paypal::Notification.ipn_url
    end

    @currency = Confline.get_value("Paypal_Default_Currency", @user.owner_id)

    @payment = Payment.new do |p|
      p.gross = @amount
      p.amount = @amount_with_vat
      p.completed = 0
      p.paymenttype = 'paypal'
      p.email = Confline.get_value("PayPal_Email", @user.owner_id)
      p.user_id = @user.id
      p.date_added = Time.now
      p.pending_reason = 'Unnotified payment'
      p.owner_id = @user.owner_id
      p.currency = @currency.to_s
    end
    @payment.save
  end


  def paypal_ipn
    MorLog.my_debug('paypal_ipn accessed', true)

    notify = Paypal::Notification.new(request.raw_post)
    if notify.reversed?
      @payment = Payment.find(:first, :conditions => ["id = ?", notify.item_id])
    else
      @payment = Payment.find(:first, :conditions => ["id = ? AND completed = 0", notify.item_id])
    end
    if @payment
      @user = @payment.user
      if @user
        if Confline.get_value("PayPal_Enabled", @user.owner_id).to_i == 0
          dont_be_so_smart
          redirect_to :controller => "callc", :action => "main" and return false
        end

        if Confline.get_value("PayPal_Test", @user.owner_id).to_i == 1
          @paypal_url = Paypal::Notification.test_ipn_url
        else
          @paypal_url = Paypal::Notification.ipn_url
        end

        if notify.acknowledge(@paypal_url)
          MorLog.my_debug("notify acknowledged : #{@payment.id}", true)
          MorLog.my_debug("found user : #{@user.id}", true)

          paypal_email = Confline.get_value("PayPal_Email", @user.owner_id).to_s
          # we keep original amount (which he specified in payment form) in custom field so that we could compare
          if paypal_email.to_s.downcase.to_s.strip == notify.business.to_s.downcase.to_s.strip and @payment.amount.to_d == notify.custom.to_d
            MorLog.my_debug("business email is valid", true)
            if notify.complete?
              @payment.fee = notify.fee.to_d
              @payment.amount = notify.gross.to_d
              @payment.gross = notify.gross.to_d - notify.tax.to_d
              @payment.tax = notify.tax.to_d
              @payment.paymenttype = 'paypal'
              @payment.currency = notify.currency.to_s
              @payment.transaction_id = notify.transaction_id.to_s
              @payment.first_name = notify.first_name.to_s
              @payment.last_name = notify.last_name.to_s
              @payment.payer_email = notify.payer_email.to_s
              @payment.residence_country = notify.residence_country.to_s
              @payment.payer_status = notify.payer_status.to_s
              @payment.user_id = @user.id
              @payment.date_added = Time.now if not @payment.date_added
              @payment.pending_reason = notify.pending_reason.to_s
              @payment.pending_reason = "Denied" if notify.status == "Denied"
              @payment.pending_reason = "Reversed" if notify.reversed?
              @payment.owner_id = @user.owner_id
              @payment.completed = 1
              @payment.save
              confirmation = Confline.get_value("PayPal_Payment_Confirmation", @user.owner_id).to_s

              if confirmation.blank? or confirmation == "none" or (confirmation == "suspicious" and notify.payer_email.to_s == @user.email)
                @payment.shipped_at = (notify.complete?) ? Time.now : nil
                MorLog.my_debug("User balance before payment: #{@user.balance}")
                @user.balance += sprintf("%.2f", @payment.gross * Currency.count_exchange_rate(@payment.currency, Currency.find(1).name)).to_d
                if @payment.fee.to_d != 0.0 and Confline.get_value("PayPal_User_Pays_Transfer_Fee", @user.owner_id).to_i == 1
                  @user.balance -= sprintf("%.2f", @payment.fee * Currency.count_exchange_rate(@payment.currency, Currency.find(1).name)).to_d
                  fee_payment = @payment.dup
                  fee_payment.paymenttype = "paypal_fee"
                  fee_payment.fee = 0
                  fee_payment.tax = 0
                  fee_payment.shipped_at = Time.now
                  fee_payment.completed = 1
                  fee_payment.pending_reason = "Completed"
                  fee_payment.amount = @payment.fee*-1
                  fee_payment.gross = @payment.fee*-1
                  fee_payment.save
                  Action.add_action(@user.id, "PayPal", "User paid paypal fee: #{@payment.fee} #{@payment.currency}")
                end
                @user.save
                MorLog.my_debug("PayPal balance")
                MorLog.my_debug("User balance after payment: #{@user.balance}")
                Action.add_action(@user.id, "PayPal", "Payment completed: #{@payment.amount} #{@payment.currency}")
                MorLog.my_debug('transaction succesfully completed', true)
              else # confirmation is required for all payments
                @payment.completed = 0
                @payment.pending_reason = "Waiting for confirmation"

                Action.add_action(@user.id, "PayPal", "Payment waiting for approval: #{@payment.id} #{@payment.payer_email} #{@payment.amount} #{@payment.currency}")
                MorLog.my_debug('transaction waiting for confirmation', true)

                if Confline.get_value("PayPal_Email_Notification", @user.owner_id).to_i == 1
                  email = Email.find(:first, :conditions => {:name => 'payment_notification_integrations', :owner_id => @user.owner_id})
                  user = User.where(:id => @user.owner_id).first

                  variables = Email.email_variables(user, nil, {:payment => @payment, :payment_notification => notify, :payment_type => "paypal"})
                  EmailsController::send_email(email, Confline.get_value("Email_from", user.id), [user], variables)
                  MorLog.my_debug('confirmation email sent', true)
                end
              end
            elsif notify.reversed?
              @payment.paypal_refund_payment(notify, @user)
            else
              MorLog.my_debug("transaction pending: #{notify.status}", true)
            end

            @payment.save
          else
            MorLog.my_debug('Hack attempt: Email is not equal as paypal account email or sum was changed by editing HTML', true)
            MorLog.my_debug("Expected: '#{paypal_email.to_s.downcase}'", true)
            MorLog.my_debug("Paypal:   '#{notify.business.to_s.downcase}'", true)
            Action.add_action(@user.id, "PayPal", "Hack attempt - Email #{notify.business.to_s.downcase} is not equal as paypal account email #{paypal_email.to_s.downcase} or sum was changed by editing HTML")
          end
        else
          MorLog.my_debug('notify NOT acknowledged', true)
        end
      else
        MorLog.my_debug('transaction NOT completed (User NOT found)', true)
        dont_be_so_smart
        redirect_to :controller => "callc", :action => "main" and return false
      end
    else
      MorLog.my_debug('transaction NOT completed (Payment NOT found)')
      dont_be_so_smart
      redirect_to :controller => "callc", :action => "main" and return false
    end
    render :nothing => true
  end


  # before_filter
  #   find_user_session
  #   find_payment
  def confirm_payment
    unless @payment.user.owner_id == @user.id || @user.is_admin?
      flash[:notice] = _("Not_authorized_to_confirm_payment")
      redirect_to :controller => "callc", :action => "main" and return false
    end

    user = @payment.user
    exchange_rate = Currency.count_exchange_rate(@payment.currency, Currency.find(1).name)
    # round to cents rounds to floor.
    user.balance += round_to_cents(@payment.payment_amount * exchange_rate.to_d)

    if @payment.paymenttype == "paypal" and @payment.fee.to_d != 0.0 and Confline.get_value("PayPal_User_Pays_Transfer_Fee", user.owner_id).to_i == 1
      # sprintf rounds to ceiling.
      user.balance -= sprintf("%.2f", @payment.fee * exchange_rate).to_d
      fee_payment = @payment.dup
      fee_payment.paymenttype = "paypal_fee"
      fee_payment.fee = 0
      fee_payment.tax = 0
      fee_payment.completed = 1
      fee_payment.pending_reason = "Completed"
      fee_payment.amount = @payment.fee*-1
      fee_payment.gross = @payment.fee*-1
      fee_payment.shipped_at = Time.now
      fee_payment.save
      Action.add_action(user.id, "PayPal", "User paid paypal fee: #{@payment.fee} #{@payment.currency}")
      user.save
    end

    Action.add_action_hash(user.id,
                           {:action => "payment_confirmation",
                            :data => "Payment confirmed",
                            :data2 => "payment id: #{@payment.id}",
                            :data3 => "#{@payment.amount} #{@payment.currency}"
                           })

    user.save

    MorLog.my_debug('transaction succesfully confirmed')

    @payment.update_attributes({:completed => 1, :pending_reason => "Completed", :shipped_at => Time.now})
    flash[:status] = _('Payment_confirmed')

    redirect_back_or_default("/payments/list")
  end

  def fix_paypal_payments
    change_date
    @payments = Payment.find(:all, :conditions => ["paymenttype = 'paypal' AND date_added BETWEEN ? AND ? ", session_from_datetime, session_till_datetime])

    MorLog.my_debug("DELETE FROM payments WHERE id IN (#{@payments.map { |p| p.id }.join(",")});")

    insert = []
    insert_header = "INSERT INTO payments (`id`, `tax`, `completed`, `paymenttype`, `shipped_at`, `hash`, `pending_reason`, `amount`, `transaction_id`, `card`, `owner_id`, `fee`, `gross`, `user_id`, `vat_percent`, `last_name`, `bill_nr`, `currency`, `date_added`, `payer_status`, `payer_email`, `residence_country`, `email`, `first_name`)"
    @payments.each { |payment|
      insert << "(#{payment.id},#{payment.tax},#{payment.completed},'#{payment.paymenttype}','#{payment.shipped_at.to_s(:db) if payment.shipped_at}','#{payment.payment_hash}','#{payment.pending_reason}',#{payment.amount},'#{payment.transaction_id}',#{payment.card},#{payment.owner_id},#{payment.fee},#{payment.gross},#{payment.user_id},#{payment.vat_percent},'#{payment.last_name}',#{payment.bill_nr},'#{payment.currency}','#{payment.date_added.to_s(:db) if payment.date_added}', '#{payment.payer_status}','#{payment.payer_email}','#{payment.residence_country}','#{payment.email}','#{payment.first_name}')".gsub("''", "NULL").gsub(",,", ",NULL,")
      if payment.gross.to_d == 0.0
        payment.gross = payment.amount.to_d - payment.tax.to_d
      else
        payment.amount = payment.gross.to_d
        payment.gross = payment.amount.to_d - payment.tax.to_d
      end
      payment.save
      if insert.size > 1000
        MorLog.my_debug("#{insert_header} VALUES#{insert.join(",")};")
        insert = []
      end
    }
    MorLog.my_debug("#{insert_header} VALUES#{insert.join(",")};")

    flash[:notice] = _("Payments_converted")
    redirect_to :controller => "callc", :action => "global_settings" and return false
  end

  ########### PERSONAL ##########

  def personal_payments
    #@user in before filter
    @page_title = _('Payments')
    @page_icon = "creditcards.png"
    @payments = @user.payments
  end

  #--------------- manual payments ------------

  def manual_payment
    @page_title = _('Add_manual_payment')
    @page_icon = "add.png"
    @users = []
    unless params[:user_id].blank?
      user = User.find(:first,:include => [:tax], :conditions => ["users.id = ?", params[:user_id]])
      unless user
        flash[:notice] = _('User_was_not_found')
        redirect_to :controller => "callc", :action => "main" and return false
      end
      @users = [user].compact
    else
      if params[:provider_id]
        @provider = current_user.providers.find(:first, :conditions => ["providers.id = ?", params[:provider_id]])
        unless @provider
          flash[:notice] = _('Provider_was_not_found')
          redirect_to :controller => "callc", :action => "main" and return false
        end

      else

        @user = nil
        (session[:usertype] == "admin" or session[:usertype] == "accountant") ? owner_id = 0 : owner_id = session[:user_id].to_i
        @users = User.find(:all, :conditions => ["hidden = 0 AND owner_id = ?", owner_id], :order => "first_name ASC")

        if !@users or @users.size == 0
          flash[:notice] = _('No_users_to_make_payments')
          redirect_to :controller => :payments, :action => :list and return false
        end
      end
    end
    @currs = Currency.find(:all, :conditions => ["active = '1'"])
  end

  def manual_payment_status
    @page_title = _('Add_manual_payment')
    @page_icon = "add.png"

    if params[:provider_id]
      @provider = current_user.providers.find(:first, :conditions => ["providers.id = ?", params[:provider_id]])
      unless @provider
        flash[:notice] = _('Provider_was_not_found')
        redirect_to :controller => "callc", :action => "main" and return false
      end

      user = @provider.device.user if @provider.device and @provider.device.user
      if !params[:amount].blank?
        @amount =  params[:amount].to_d
        @am_typ = "ammount"
        @real_amount = user ?  user.get_tax.apply_tax(@amount) : @amount
      else
        @am_typ = "amount_with_tax"
        @real_amount = params[:amount_with_tax].to_d #if !params[:amount_with_tax].blank?
        @amount  = user ?  user.get_tax.count_amount_without_tax(@real_amount) : @real_amount
      end

    else
      @user = User.find(:first,:include => [:tax], :conditions => ["users.id = ?" ,params[:user]])
      unless @user
        Action.add_action(session[:user_id], "error", "User: #{params[:user]} was not found") if session[:user_id].to_i != 0
        dont_be_so_smart
        redirect_to :controller => "callc", :action => "main" and return false
      end
      if !params[:amount].blank?
        @amount =  params[:amount].to_d
        @am_typ = "ammount"
        @real_amount = @user.get_tax.apply_tax(@amount)
      else
        @am_typ = "amount_with_tax"
        @real_amount = params[:amount_with_tax].to_d #if !params[:amount_with_tax].blank?
        @amount  = @user.get_tax.count_amount_without_tax(@real_amount)
      end
    end

    @curr = params[:p_currency]
    @curr_amount =  @amount.to_d
    @curr_real_amount =  @real_amount.to_d
    @description = params[:description]
    @exchange_rate = count_exchange_rate(current_user.currency.name, @curr)
    @amount = @amount.to_d /  @exchange_rate.to_d
    @real_amount = @real_amount.to_d /  @exchange_rate.to_d
    if @amount.to_d == 0.to_d
      flash[:notice] = _('Please_add_correct_amount')
      redirect_to :action => 'manual_payment'
    end
  end



  def manual_payment_finish

    if params[:provider_id]

      # manual payment for provider

      provider = current_user.providers.find(:first, :conditions => ["providers.id = ?", params[:provider_id]])
      amount = params[:amount].to_d * -1.to_d
      real_amount = params[:real_amount].to_d * -1.to_d
      currency = params[:p_currency]
      exchange_rate = count_exchange_rate(current_user.currency.name,currency)

      unless provider
        # Action.add_action(session[:user_id], "error", "User: #{params[:provider_id]} was not found") if session[:user_id].to_i != 0
        dont_be_so_smart
        redirect_to :controller => "callc", :action => "main" and return false
      end

      curr_amount =  amount / exchange_rate.to_d
      curr_real_amount =  real_amount / exchange_rate.to_d
      provider.balance +=  curr_amount
      provider.save

      usd = provider.device.user if provider.device and provider.device.user
      paym = Payment.new
      paym.paymenttype = 'manual'
      paym.amount = real_amount
      paym.currency = currency
      paym.date_added = Time.now
      paym.shipped_at = Time.now
      paym.completed = 1
      paym.user_id = usd ? usd.id : -1
      paym.provider_id = provider.id
      paym.owner_id = provider.user_id
      paym.tax = usd ? usd.get_tax.count_tax_amount(amount) : amount
      paym.description = params[:description].to_s
      paym.save
      flash[:status] = _('Payment_added')
    else

      #manual payment for user

      user = User.find(:first,:include => [:tax], :conditions => ["users.id = ?", params[:user]])
      amount = params[:amount].to_d
      real_amount = params[:real_amount].to_d
      currency = params[:p_currency]
      exchange_rate = count_exchange_rate(current_user.currency.name,currency)

      unless user
        Action.add_action(session[:user_id], "error", "User: #{params[:user]} was not found") if session[:user_id].to_i != 0
        dont_be_so_smart
        redirect_to :controller => "callc", :action => "main" and return false
      end

      curr_amount =  amount / exchange_rate.to_d
      curr_real_amount =  real_amount / exchange_rate.to_d

      #logger.fatal "#{Time.now}  -  Manual Payment TRY TO ADD - User:#{user.id}; balance:#{user.balance}; amount_to_add:#{curr_amount}"

      user.balance +=  curr_amount
      if user.save
        #logger.fatal "#{Time.now}  -  Manual Payment User saved - User:#{user.id}; balance:#{user.balance}"

        paym = Payment.new
        paym.paymenttype = 'manual'
        paym.amount = real_amount
        paym.currency = currency
        paym.date_added = Time.now
        paym.shipped_at = Time.now
		paym.fee = 0
        paym.completed = 1
        paym.user_id = user.id
        paym.owner_id = user.owner_id
        paym.tax = user.get_tax.count_tax_amount(amount)
        paym.description = params[:description].to_s
        paym.save
        #logger.fatal "#{Time.now}  -  Manual Payment Payment created - Payment:#{paym.id}; amount:#{paym.amount}; amount_to_add:#{real_amount}"


        invoice_amount = (curr_amount/ current_user.current.currency.exchange_rate.to_d).to_d
        invoice_amount_real = (curr_real_amount/ current_user.current.currency.exchange_rate.to_d).to_d

        nc=nice_invoice_number_digits("prepaid")
        # create invoice for prepaid user's manual payment if such setting activated
        if user.postpaid == 0 and user.generate_invoice == 1
          number_type = Confline.get_value("Prepaid_Invoice_Number_Type").to_i
          invoice = Invoice.new
          invoice.user_id = user.id
          invoice.tax = user.tax.dup
          invoice.period_start =  Time.now
          invoice.period_end =  Time.now
          invoice.issue_date = Time.now
          invoice.paid = 1
          invoice.number = ""
          invoice.paid_date = Time.now
          invoice.invoice_type = "prepaid"
          invoice.price = invoice.nice_invoice_number(invoice_amount.to_d, {:nc=>nc, :apply_rounding=>true})
          invoice.price_with_vat = invoice.nice_invoice_number(invoice_amount_real.to_d, {:nc=>nc, :apply_rounding=>true})
          invoice.invoice_precision=nc
          invoice.save

          invoice.number = generate_invoice_number(Confline.get_value("Prepaid_Invoice_Number_Start"), Confline.get_value("Prepaid_Invoice_Number_Length").to_i, number_type, invoice.id, Time.now)
          invoice.number_type = number_type
          invoice.save

          invdetail = Invoicedetail.new
          invdetail.invoice_id = invoice.id

          if currency.to_s != current_user.currency.name
            invdetail.name = _('Manual_payment') + "(#{params[:amount].to_d} #{currency.to_s})"
          else
            invdetail.name = _('Manual_payment')
          end

          invdetail.price = invoice_amount.to_d
          invdetail.quantity = 1
          invdetail.invdet_type = 0
          invdetail.save
        else
          Action.add_action_hash(current_user, :target_id => user.id, :target_type => 'user', :action => "invoice_not_created")
        end
        
    if !user.address.mob_phone.blank?
        #START ----- Send Notification by SMS
        @user1 = User.where(:id => 0).first
        message = _('Body_message_new_payment', paym.paymenttype.to_s, paym.amount.to_s, user.username.to_s, nice_number(user.balance.to_d).to_s)
        sms = SmsMessage.new
        sms.sending_date = Time.now
        sms.user_id = @user1.id
        sms.reseller_id = @user1.owner_id
        sms.number = user.address.mob_phone
        sms.sms_type = "payment"
        sms.reg_owner = user.owner_id
        sms.save
      if Confline.get_value("Send_fake_SMS_for_mobile_validation", user.owner_id).to_i == 0
          Thread.new {
            sms.sms_send(@user1, @user1.sms_tariff, sms.number, @user1.sms_lcr, 1, message)
          }
        else
          sms.status_code = "7"
          sms.save
        end
        #END ----- Send Notification by SMS
    end		
		if !user.email.blank?
			begin
				a = Thread.new {
				  send_email_to_user = EmailsController.send_user_email_after_payment(user, {:payment_amount => paym.amount, :payment_date => paym.shipped_at, :payment_fee => paym.fee, :payment_currency => paym.currency, :payment_type => paym.paymenttype})
				  #EmailsController.send_admin_email_after_registration(user, device, params[:password], reg_ip, free_ext, owner.id)
				}
			rescue Exception => e
			  Action.add_action(user.id, "Manual", "Email not sent to user #{user.username} after payment: #{paym.amount} #{paym.currency}")
			end
		else
			 Action.add_action(user.id, "Manual", "User #{user.username} was not emailed after payment: #{paym.amount} #{paym.currency}. Email for is not registered.")
		end
        flash[:status] = _('Payment_added')
      else
        #logger.fatal "#{Time.now}  -  Manual Payment User NOT saved - User:#{user.id}; balance:#{user.balance}; amount_to_add:#{curr_amount}"
        flash_errors_for(_('Payment_failed'), user)
      end
    end
    redirect_to :action => 'list'
  end


  def delete_payment
    paym = Payment.find(:first, :conditions => ["id = ?", params[:id]])
    unless paym
      flash[:notice] = _('Payment_was_not_found')
      redirect_to :action => 'list' and return false
    end

    if not ["manual", "credit note"].include? paym.paymenttype
      flash[:notice] = _('Only_manual_or_credit_note_payments_can_be_deleted')
      redirect_to :action => 'list' and return false
    end

    if paym.owner_id != current_user.id
      flash[:notice] = _('Forbidden_to_delete_payments')
      dont_be_so_smart
      redirect_to :action => 'list' and return false
    end

    user = User.find(:first, :include => [:tax], :conditions => ["users.id = ?", paym.user_id])
    if user and user.class == User
      real_amount = user.get_tax.count_amount_without_tax(paym.amount) / Currency::count_exchange_rate(current_user.currency.name, paym.currency)
      user.balance -= real_amount
      user.save
    end

    paym.destroy
    if paym.paymenttype == "credit note"
      paym.destroy_credit_note
    end

    flash[:notice] = _('Payment_deleted')
    redirect_to :action => 'list'
  end
  
	########### SafetyPay. Added by Adesh. #########

  def safetypay
    #@user in before filter
    @page_title = _('SafetyPay')
    @page_icon = "money.png"
    @enabled = Confline.get_value("SafetyPay_Enabled", @user.owner_id).to_i
    @currency = Confline.get_value("SafetyPay_Default_Currency", @user.owner_id)
  end
  
  def safetypay_pay 
    #@user in before filter
    @page_title = _('SafetyPay')
    @page_icon = "money.png"
	owner_id = @user.owner_id
    @enabled = Confline.get_value("SafetyPay_Enabled", owner_id).to_i
    if @enabled == 1
		
      @safetypay_success = Web_URL + Web_Dir + "/payments/personal_payments"
      @safetypay_fail = Web_URL + Web_Dir + "/callc/main"


      @amount = Confline.get_value("SafetyPay_Default_Amount", owner_id).to_d
      @amount = params[:amount].to_d if params[:amount]

      spay_min_amount = Confline.get_value("SafetyPay_Min_Amount", owner_id).to_d

      @amount = spay_min_amount if @amount < spay_min_amount
     
      @amount_with_vat = @user.get_tax.apply_tax(@amount) 
      @test = Confline.get_value('SafetyPay_Test', owner_id)
	  @currency = Confline.get_value('SafetyPay_Default_Currency', owner_id) #
	  @apikey = Confline.get_value("SafetyPay_Key", owner_id) 
	  @language = Confline.get_value("SafetyPay_Lang", owner_id)  
	  @company_name = session[:company] 
	  @shopper_email = @user.email 
	  @safetypay_signature = Confline.get_value("SafetyPay_Signature", owner_id) 

      @payment = Payment.new
      @payment.paymenttype = 'SafetyPay'
      @payment.amount = @amount_with_vat
      @payment.currency = @currency
      @payment.date_added = Time.now
      @payment.completed = 0
      @payment.gross = @amount
      @payment.first_name = session[:first_name]
      @payment.last_name = session[:last_name]
      @payment.tax = @amount_with_vat - @amount
      @payment.user_id = session[:user_id]
      @payment.pending_reason = 'Unnotified payment'
      @payment.owner_id = owner_id
      @payment.save
      @payment_id = @payment.id
	  
	  @safetypay_token_url = safetypay_token(@payment_id, @amount_with_vat, @apikey, :currency => @currency, :language => @language, :success_url => @safetypay_success, :fail_url => @safetypay_fail, :company_name => @company_name, :shopper_email => @shopper_email, :test => @test, :safetypay_signature => @safetypay_signature)

	  if @safetypay_token_url.blank?
		flash[:notice] = _("SafetyPay_Error_Occurred")
        redirect_to :controller => "callc", :action => "main" and return false		
	  end
   end

  end
  
    def safetypay_ipn
		MorLog.my_debug('safety_ipn accessed', true)
		if Confline.get_value("SafetyPay_Enabled", 0).to_i == 1
			test = Confline.get_value("SafetyPay_Test", 0)	
			apiKey = Confline.get_value("SafetyPay_Key", 0).to_s
			requestDateTime =  Time.now.iso8601.truncate(19, omission: '')
			safetypay_signature = Confline.get_value("SafetyPay_Signature", 0).to_s
			safetypay_fee_percent = Confline.get_value("SafetyPay_Fee_Percent", 0).to_d
			signature = Digest::SHA256.hexdigest(requestDateTime + safetypay_signature)	
			message1 = { "ApiKey" => apiKey, "RequestDateTime"=> requestDateTime, "Signature"=> signature  }
			if test.to_i == 1
				client = Savon.client(wsdl: "/home/mor/public/safetypay/MerchantExpressWs.wsdl", namespaces: {"xmlns:urn" => "urn:safetypay:messages:mws:api"}, namespace_identifier: :urn, env_namespace: :soapenv, convert_request_keys_to: :none)
			else
			#Instance the client in production
				client = Savon.client(wsdl: "/home/mor/public/safetypay/MerchantExpressWs_prod.wsdl", namespaces: {"xmlns:urn" => "urn:safetypay:messages:mws:api"}, namespace_identifier: :urn, env_namespace: :soapenv, convert_request_keys_to: :none)
			end
			response = client.call(:get_new_operation_activity,  message_tag: :OperationActivityRequest, message: message1 )
			if response.success?
				response = response.body
				data = response[:operation_response]		
				if data[:error_manager][:error_number].to_i == 0
					if data[:list_of_operations]
						requestDateTime =  Time.now.iso8601.truncate(19, omission: '')
						signature_string =  requestDateTime
						message2 = {"ApiKey" => apiKey, "RequestDateTime"=> requestDateTime}
						listOfOperationsActivityNotified = Array.new
						i = 0
						status_code = nil
						merchant_sales_id = nil
						merchant_order_id = nil
						fee_payment = nil
						data_cycle = Array.new
						if data[:list_of_operations][:operation][1]
							data_cycle = data[:list_of_operations][:operation]
						else
							data_cycle[0] = data[:list_of_operations][:operation]
						end
						data_cycle.each do |l|			
							signature_string += l[:operation_id].to_s
							merchant_sales_id = l[:merchant_sales_id].to_s
							signature_string += merchant_sales_id
							merchant_order_id = l[:merchant_sales_id].to_s
							signature_string += merchant_order_id				
							l[:creation_date_time].iso8601.truncate(19, omission: '')
							status_code = l[:operation_activities][:operation_activity][:status][:status_code].to_s
							signature_string += status_code
							
							@payment = Payment.find(:first, :conditions => ["id = ? AND completed = 0", merchant_sales_id])
							if @payment and @payment.amount == l[:amount].to_d and @payment.currency == l[:currency_id].to_s
								@user = @payment.user
								@payment.fee = l[:amount].to_d * safetypay_fee_percent/100
								@payment.gross = l[:amount].to_d
								@payment.tax = 0
								@payment.paymenttype = 'SafetyPay'								
								@payment.transaction_id = l[:operation_id].to_s
								@payment.date_added = Time.now if not @payment.date_added
								@payment.shipped_at = Time.now
								@payment.pending_reason = l[:operation_activities][:operation_activity][:status][:description].to_s
								@payment.owner_id = @user.owner_id  
								@payment.bill_nr = l[:payment_reference_no]
								@payment.completed = 1
								@payment.save
		
								MorLog.my_debug("SafetyPay: User balance before payment: #{@user.balance}")
								@user.balance += sprintf("%.2f", @payment.gross * Currency.count_exchange_rate(@payment.currency, Currency.find(1).name)).to_d
								if @payment.fee.to_d != 0.0
									fee_payment = @payment.dup
									fee_payment.paymenttype = "commission_for_payment_transaction"									
									fee_payment.fee = 0
									fee_payment.amount =  @payment.fee*(-1)
									fee_payment.gross = @payment.fee*(-1)
									fee_payment.save
									@user.balance -= sprintf("%.2f", @payment.fee * Currency.count_exchange_rate(@payment.currency, Currency.find(1).name)).to_d
									Action.add_action(@user.id, "SafetyPay", "User paid fee for SafetyPay: #{@payment.fee} #{@payment.currency}")
								end
								@user.save
                if !@user.address.mob_phone.blank?
                    #START ----- Send Notification by SMS
                    @user1 = User.where(:id => 0).first
                    message = _('Body_message_new_payment', @payment.paymenttype.to_s, @payment.amount.to_s, @user.username.to_s, nice_number(@user.balance.to_d).to_s)
                    sms = SmsMessage.new
                    sms.sending_date = Time.now
                    sms.user_id = @user1.id
                    sms.reseller_id = @user1.owner_id
                    sms.number = @user.address.mob_phone
                    sms.sms_type = "payment"
                    sms.reg_owner = @user.owner_id
                    sms.save
                    if Confline.get_value("Send_fake_SMS_for_mobile_validation", @user.owner_id).to_i == 0
                      Thread.new {
                        sms.sms_send(@user1, @user1.sms_tariff, sms.number, @user1.sms_lcr, 1, message)
                      }
                    else
                      sms.status_code = "7"
                      sms.save
                    end
                    #END ----- Send Notification by SMS
                end		
								if !@user.email.blank?
									User.current = @user
									begin
										a = Thread.new {
										  send_email_to_user = EmailsController.send_user_email_after_payment(@user, {:payment_amount => @payment.amount, :payment_date => @payment.shipped_at, :payment_fee => @payment.fee, :payment_currency => @payment.currency, :payment_type => @payment.paymenttype})
										  #EmailsController.send_admin_email_after_registration(user, device, params[:password], reg_ip, free_ext, owner.id)
										}
									rescue Exception => e
									  Action.add_action(@user.id, "SafetyPay", "Email not sent to user #{@user.username} after payment: #{@payment.amount} #{@payment.currency}")
									end
								else
									 Action.add_action(@user.id, "SafetyPay", "User #{@user.username} was not emailed after payment: #{@payment.amount} #{@payment.currency}. Email for is not registered.")
								end
								
								MorLog.my_debug("SafetyPay: User balance after payment: #{@user.balance}")
								Action.add_action(@user.id, "SafetyPay", "Payment completed: #{@payment.amount} #{@payment.currency}")
								MorLog.my_debug('SafetyPay: Transaction succesfully completed', true)
							else
							MorLog.my_debug('SafetyPay: Non-completed merchant_sales_id doesnt exist or amount mismatch or currency mismatch)', true)								
							end
							
							listOfOperationsActivityNotified[i] = { "urn1:CreationDateTime" => l[:creation_date_time].iso8601.truncate(19, omission: ''), "urn1:OperationID" => l[:operation_id], "urn1:MerchantSalesID" => l[:merchant_sales_id], "urn1:MerchantOrderID" => merchant_order_id, "urn1:OperationStatus" => status_code }
							i = i + 1
						end

						listOfOperationsActivityNotified = { "urn:ListOfOperationsActivityNotified" => {"urn1:ConfirmOperation" => listOfOperationsActivityNotified} }
						message2 = message2.merge(listOfOperationsActivityNotified)
						signature_string += safetypay_signature
						signature = Digest::SHA256.hexdigest(signature_string)
						message2 = message2.merge({ "Signature"=> signature  })
						if test.to_i == 1
							client = Savon.client(wsdl: "/home/mor/public/safetypay/MerchantExpressWs.wsdl", namespaces: {"xmlns:urn" => "urn:safetypay:messages:mws:api",   "xmlns:urn1"  =>"urn:safetypay:schema:mws:api"}, namespace_identifier: :urn, env_namespace: :soapenv, convert_request_keys_to: :none)
						else
						####Write (instance) the client in production
							client = Savon.client(wsdl: "/home/mor/public/safetypay/MerchantExpressWs_prod.wsdl", namespaces: {"xmlns:urn" => "urn:safetypay:messages:mws:api",   "xmlns:urn1"  =>"urn:safetypay:schema:mws:api"}, namespace_identifier: :urn, env_namespace: :soapenv, convert_request_keys_to: :none)
						end
						response = client.call(:confirm_new_operation_activity, message_tag: :OperationActivityNotifiedRequest, message: message2 )	
					else
					MorLog.my_debug('SafetyPay: get_new_operation_activity, :list_of_operations is null', true)
					return	#An error is being launched. Unexpected return.
					end
				else
				MorLog.my_debug('SafetyPay: get_new_operation_activity, error != 0', true)
				return
				end
			else
			MorLog.my_debug('SafetyPay: get_new_operation_activity, SOAP failed', true)	
			return		
			end
		else
		MorLog.my_debug('safetypay_ipn: SafetyPay is not enabled', true)
		end
	end


  ########### END SafetyPay #########

  def webmoney
    #@user in before filter
    @page_title = _('WebMoney')
    @page_icon = "money.png"
    @enabled = Confline.get_value("WebMoney_Enabled", @user.owner_id).to_i
    @currency = Confline.get_value("WebMoney_Default_Currency", @user.owner_id)
  end

=begin rdoc

=end

  def webmoney_pay
    #@user in before filter
    @page_title = _('WebMoney')
    @page_icon = "money.png"
    @enabled = Confline.get_value("WebMoney_Enabled", @user.owner_id).to_i
    if @enabled == 1
	
      @webmoney_result_url = Web_URL + Web_Dir + "/payments/webmoney_result"
      @webmoney_fail_url = Web_URL + Web_Dir + "/payments/webmoney_fail"
      @webmoney_success_url = Web_URL + Web_Dir + "/payments/webmoney_success"

      #@user = User.find(session[:user_id])
      @user_id = session[:user_id]


      @amount = Confline.get_value("WebMoney_Default_Amount", @user.owner_id).to_d
      @amount = params[:amount].to_d if params[:amount]

      wm_min_amount = Confline.get_value("WebMoney_Min_Amount", @user.owner_id).to_d

      @amount = wm_min_amount if @amount < wm_min_amount
      @test = Confline.get_value('WebMoney_Test', @user.owner_id)
      @test_mode = Confline.get_value('WebMoney_SIM_MODE', @user.owner_id)

      @amount_with_vat = @user.get_tax.apply_tax(@amount)
      @currency = confline('WebMoney_Default_Currency')  #Maybe there coould occurr an error here in some cases
      @description = session[:company] + " balance update"
	  
      @payment = Payment.new
      @payment.paymenttype = 'webmoney'
      @payment.amount = @amount_with_vat
      @payment.currency = Confline.get_value('WebMoney_Default_Currency', @user.owner_id)
      @payment.date_added = Time.now
      @payment.completed = 0
      @payment.gross = @amount
      @payment.first_name = session[:first_name]
      @payment.last_name = session[:last_name]
      @payment.tax = @amount_with_vat - @amount
      @payment.user_id = session[:user_id]
      @payment.pending_reason = 'Unnotified payment'
      @payment.owner_id = @user.owner_id
      @payment.save
      @payment_id = @payment.id
    end

  end

  def webmoney_result

    my_debug ""
    my_debug "===== Webmoney result reached ====="
    my_debug params.to_yaml

    #@user = User.find(params[:user])
    @enabled = Confline.get_value("WebMoney_Enabled", 0).to_i
    @test = Confline.get_value('WebMoney_Test', 0).to_i
    @skip_prerequest = Confline.get_value('Webmoney_skip_prerequest', 0).to_i
    if  params[:LMI_PREREQUEST].to_i == 1 && @enabled == 1
      @payment = Payment.find(params[:LMI_PAYMENT_NO])
      if @payment
        if @payment.amount.to_d == params[:LMI_PAYMENT_AMOUNT].to_d
          if params[:LMI_PAYEE_PURSE].to_s == confline("WebMoney_Purse").to_s
            @payment.pending_reason = 'Notified payment'
            @payment.save
            @view_var = "YES"
            render(:layout => false) and return false
          else
            @viev_var = "Wrong purse."
          end
        else
          @view_var = "Amount mismach."
        end
      else
        @view_var = "Payment not found."
      end

    else
      @payment = Payment.find(:first, :conditions => "id = #{params[:LMI_PAYMENT_NO].to_i}")
      if @payment
        if @payment.pending_reason.to_s == 'Notified payment' or @skip_prerequest == 1
          if @payment.amount.to_d == params[:LMI_PAYMENT_AMOUNT].to_d
            if params[:LMI_MODE].to_i == confline('WebMoney_Test').to_i
              if params[:LMI_PAYEE_PURSE].to_s == confline('WebMoney_Purse').to_s
                @hash_str = ''
                @hash_str += params[:LMI_PAYEE_PURSE].to_s
                @hash_str += params[:LMI_PAYMENT_AMOUNT].to_s
                @hash_str += params[:LMI_PAYMENT_NO].to_s
                @hash_str += params[:LMI_MODE].to_s
                @hash_str += params[:LMI_SYS_INVS_NO].to_s
                @hash_str += params[:LMI_SYS_TRANS_NO].to_s
                @hash_str += params[:LMI_SYS_TRANS_DATE].to_s
                #                   If Server does not using SSL, Secret Key is not in request,
                #                   so we need to store it in database
                #                   Fixed by A.Mazunin
                #                  if params[:LMI_SECRET_KEY].to_s==''
                #                    @hash_str += confline('WebMoney_Purse').to_s
                #                  else
                #                    @hash_str +=params[:LMI_SECRET_KEY].to_s
                #                  end
                secret_key = Confline.get_value("WebMoney_Secret_key").to_s
                if secret_key and secret_key.length>0
                  @hash_str+= secret_key
                end

                @hash_str += params[:LMI_PAYER_PURSE].to_s
                @hash_str += params[:LMI_PAYER_WM].to_s
                @hash = Digest::MD5.hexdigest(@hash_str).to_s.upcase
                if @hash == params[:LMI_HASH].to_s
                  @payment.completed = 1
                  @payment.transaction_id = params[:LMI_SYS_TRANS_NO]
                  @payment.shipped_at = Time.now
                  @payment.payer_email = params[:LMI_PAYER_PURSE]
                  @payment.payment_hash = params[:LMI_HASH]
                  @payment.bill_nr = params[:LMI_SYS_INVS_NO]
                  @payment.pending_reason = ''
                  @payment.save
                  @user = User.find(params[:user])
                  #@user.balance += params[:gross].to_d
                  @user.balance += params[:gross].to_d*Currency.count_exchange_rate(@payment.currency, @user.currency).to_d
                  @user.save
                else
                  MorLog.my_debug('Hash mismatch')
                  MorLog.my_debug('    System hash:' + @hash)
                  MorLog.my_debug('    WM     hash:' + params[:LMI_HASH].to_s)
                end
              else
                MorLog.my_debug('Payment notification : Merchant purse missmach')
                MorLog.my_debug('   SYSTEM:' + confline('WebMoney_Purse'))
                MorLog.my_debug('   WM    :' + params[:LMI_PAYEE_PURSE])
              end
            else
              MorLog.my_debug('Payment notification : Mode missmach')
              MorLog.my_debug('   SYSTEM:' + confline('WebMoney_Test'))
              MorLog.my_debug('   WM    :' + params[:LMI_MODE].to_s)
              MorLog.my_debug(params.to_yaml) if params
              MorLog.my_debug('-------------------------------------')
            end
          else
            MorLog.my_debug('Payment notification : payment amount missmach')
            MorLog.my_debug('   SYSTEM :' + @payment.amount.to_s)
            MorLog.my_debug('   WM     :' + params[:LMI_PAYMENT_AMOUNT].to_s)
          end
        else
          MorLog.my_debug('Payment notification : Payment was not prerequested')
        end
      else
        MorLog.my_debug('Payment notification : Payment was not found')
      end
      render :nothing => true and return false
    end
  end

  def webmoney_success

    MorLog.my_debug ""
    MorLog.my_debug "===== Webmoney success reached ====="
    MorLog.my_debug params.to_yaml

    if params[:LMI_PAYMENT_NO].to_i > 0
      MorLog.my_debug "payment_id received"
      @payment = Payment.find(:first, :conditions => ["id = ?", params[:LMI_PAYMENT_NO]])
      @user = User.find(session[:user_id])
      @amount = @payment.gross
    else
      MorLog.my_debug('Params in webmoney_success action')
      MorLog.my_debug(params.to_yaml) if params
      MorLog.my_debug('-------------------------------------')
      MorLog.my_debug "payment_id not received"
      redirect_to :controller => "callc", :action => 'main' and return false

    end

  end

  def webmoney_fail
    if params[:LMI_PAYMENT_NO].to_i > 0 and @payment = Payment.find(:first, :conditions => ["id =?", params[:LMI_PAYMENT_NO].to_i])
      @payment.destroy
    end
  end

  ################# Cyberplat ####################################################

  def cyberplat
    #@user in before filter
    @page_title = _('Cyberplat')
    @page_icon = "money.png"
    @enabled = Confline.get_value("Cyberplat_Enabled", @user.owner_id).to_i
    @user_enabled = @user.cyberplat_active.to_i
    @currencies = Currency.get_active
    @disabled_message = Confline.get_value2("Cyberplat_Disabled_Info", @user.owner_id)
  end

  def cyberplat_pay
    #@user in before filter
    if !File.exist?("#{Actual_Dir}/lib/cyberplat/checker.ini")
      flash[:notice] = _("Cyberplat_is_not_configured")
      Action.add_error(session[:user_id], _('Cyberplat')+": "+_("/lib/cyberplat/checker.ini_was_not_found"))
      redirect_to :controller => "callc", :action => "main" and return false
    end
    @page_title = _('Cyberplat')
    @page_icon = "money.png"
    @enabled = Confline.get_value("Cyberplat_Enabled", @user.owner_id).to_i
    @user_enabled = @user.cyberplat_active.to_i
    @test = Confline.get_value("Cyberplat_Test", @user.owner_id).to_i
    @fee = Confline.get_value("Cyberplat_Transaction_Fee", @user.owner_id).to_d
    @cp_default_curr = Confline.get_value("Cyberplat_Default_Currency", @user.owner_id)
    @cp_default_curr = "RUB" if @cp_default_curr == "RUR"
    @user_curr = @cp_default_curr
    @user_curr = params[:user_currency] if params[:user_currency]
    @language = params[:cp_language]
    @disabled_message = Confline.get_value2("Cyberplat_Disabled_Info", @user.owner_id)
    if @enabled == 1
      if @test == 1
        @submit_url = "https://payment.cyberplat.ru/cgi-bin/GetForm.cgi"
      else
        @submit_url = "https://card.cyberplat.ru/cgi-bin/GetForm.cgi"
      end

      @cyberplat_result_url = Web_URL + Web_Dir + "/payments/cyberplat_result"

      @user = User.find(:first, :include => [:tax], :conditions => ["users.id = ?", session[:user_id]])
      @user_id = session[:user_id]

      @user_amount = Confline.get_value("Cyberplat_Default_Amount", @user.owner_id).to_d
      @user_amount = params[:amount].to_d if params[:amount]
      @user_amount = sprintf("%.2f", @user_amount).to_d
      @amount = sprintf("%.2f", @user_amount * Currency.count_exchange_rate(@user_curr, @cp_default_curr)).to_d
      cp_min_amount = Confline.get_value("Cyberplat_Min_Amount", @user.owner_id).to_d

      if @amount < cp_min_amount
        @user_amount = cp_min_amount * Currency.count_exchange_rate(@cp_default_curr, @user_curr)
        @amount = cp_min_amount
      end
      @user_vat_sum = @user.get_tax.count_tax_amount(@amount)

      @user_amount_with_vat = @user_amount + @user_vat_sum
      @user_fee_sum = @user_amount_with_vat*(@fee/100)
      @user_amount_with_vat += @user_fee_sum
      @user_amount_with_vat = sprintf("%.2f", @user_amount_with_vat).to_d
      @description = session[:company] + " balance update"


      @vat_sum = sprintf("%.2f", @user_vat_sum).to_d
      @amount_with_vat = @amount + @vat_sum
      @fee_sum = @amount_with_vat*(@fee/100)
      @fee_sum = sprintf("%.2f", @fee_sum).to_d
      @amount_with_vat += @fee_sum
      @amount_with_vat = sprintf("%.2f", @amount_with_vat).to_d

      @payment = Payment.new
      @payment.paymenttype = 'cyberplat'
      @payment.amount = @amount_with_vat
      @payment.currency = @cp_default_curr
      @payment.date_added = Time.now
      @payment.completed = 0
      @payment.gross = @amount
      @payment.fee = @fee_sum
      @payment.first_name = session[:first_name]
      @payment.last_name = session[:last_name]
      @payment.tax = @vat_sum
      @payment.user_id = session[:user_id]
      @payment.pending_reason = 'Unnotified payment'
      @payment.owner_id = @user.owner_id
      @payment.save
      @payment_id = @payment.id
    end
  end

  def cyberplat_result

    @page_title = _('Cyberplat')
    @page_icon = "money.png"

    #@payment = Payment.find(:first, :conditions => "id = #{params[:orderid]}")
    if params[:orderid] == nil or (@payment = Payment.find(:first, :conditions => "id = #{params[:orderid]}")) == nil
      redirect_to :controller => 'callc', :action => 'main' and return false
    end
    @user = @payment.user
    @enabled = (Confline.get_value("Cyberplat_Enabled", @user.owner_id).to_i and @user.cyberplat_active.to_i)
    @test = Confline.get_value("Cyberplat_Test", @user.owner_id).to_i
    @cp_default_curr = Confline.get_value("Cyberplat_Default_Currency", @user.owner_id)
    checker_tmp = Confline.get_value("Cyberplat_Temporary_Directory", 0)


    if @payment and @enabled == 1
      File.open("#{checker_tmp}/message2.txt", 'w') { |f| f.write(params[:reply]) }
      system("#{Actual_Dir}/lib/cyberplat/checker.exe -c -f #{Actual_Dir}/lib/cyberplat/checker.ini #{checker_tmp}/message2.txt > #{checker_tmp}/message3.txt")
      msg = ""
      File.open("#{checker_tmp}/message3.txt", "r") do |infile|
        while (line = infile.gets)
          msg +=line
        end
      end
      system("rm #{checker_tmp}/message2.txt")
      system("rm #{checker_tmp}/message3.txt")
      MorLog.my_debug(msg)
      b = msg.split("&")
      z = []

      for s in b do
        k = []
        k[0] = s.split("=")[0]
        k[1] = s.split("=")[1]
        z += k
      end

      @status = z[z.index("Status")+1].to_i if z.index("Status")
      @transaction_id = z[z.index("TransactionID")+1].to_i if z.index("TransactionID")
      @order_id = z[z.index("OrderID")+1].to_i if z.index("OrderID")
      @transaction_amount = z[z.index("TransactionAmount")+1].to_d/100 if z.index("TransactionAmount")
      @transaction_currency = z[z.index("TransactionCurrency")+1] if z.index("TransactionCurrency")
      @error_code = z[z.index("ErrorCode")+1].to_i if z.index("ErrorCode")
      @description = z[z.index("Description")+1] if z.index("Description")
      @customer_title = z[z.index("CustomerTitle")+1] if z.index("CustomerTitle")
      @customer_name = z[z.index("CustomerName")+1] if z.index("CustomerName")
      @payment_details = z[z.index("PaymentDetails")+1] if z.index("PaymentDetails")
      @transaction_date = z[z.index("TransactionDate")+1] if z.index("TransactionDate")
      @auth_code = z[z.index("AuthCode")+1] if z.index("AuthCode")
      @terminal = z[z.index("Terminal")+1] if z.index("Terminal")
      if @status == 0
        if @payment.id == @order_id
          if @payment.pending_reason == "Unnotified payment"
            if @payment.amount == @transaction_amount
              @payment.completed = 1
              @payment.transaction_id = @transaction_id
              @payment.shipped_at = Time.now
              @payment.payer_email = @user.email
              @payment.pending_reason = ''
              @payment.save
              @user.balance += sprintf("%.2f", @payment.gross * Currency.count_exchange_rate(@payment.currency, Currency.find(1).name)).to_d
              @user.save
              email = Email.find(:first, :conditions => "name = 'cyberplat_announce' AND owner_id = #{@user.owner_id}")
              users = []
              users << @user
              users << User.find(@user.owner_id)
              variables = email_variables(user, nil, {:amount => @transaction_amount, :currency => @transaction_currency, :date => @transaction_date, :auth_code => @auth_code, :trans_id => @transaction_id, :customer_name => @customer_name, :description => @payment_details})
              EmailsController.send_email(email, session[:company_email], users, variables)
            else
              @status = 1
              @error_code = 1
              @description = _("Amount_Missmatch")
              my_debug("Amount missmatch")
              my_debug("Payment amount: "+@payment.amount.to_s)
              my_debug("Transaction amount: "+@transaction_amount.to_s)
            end
          else
            @status = 2
            @error_code = 2
            @description = _("Unknown_Payment")
            my_debug("Unnotified payment")
          end
        else
          @status = 3
          @error_code = 3
          @description = _("Unknown_Payment_ID")
          my_debug("Unnotified payment")
          my_debug("PaymentID and orderID are not equal")
          my_debug("PaymentID"+@payment.id.to_s)
          my_debug("orderID"+@order_id)
        end
      else
        my_debug("Wrong status: "+ @status.to_s)
      end
    else
      my_debug("Payment not enabled or not found")
    end
  end

  ################# /Cyberplat ###################################################


  ################# Ouroboros ####################################################


=begin rdoc
 Sets basic data for primary Ouroboros payment window.
=end

  def ouroboros
    #@user in before filter
    @page_title = _('Ouroboros')
    @page_icon = "money.png"
    @enabled = Confline.get_value("Ouroboros_Enabled", @user.owner_id).to_i
    @currencies = Currency.get_active
    @currency = Confline.get_value("Ouroboros_Default_Currency", @user.owner_id)
    @default_amount = Confline.get_value("Ouroboros_Default_Amount", @user.owner_id)
    @min_amount = Confline.get_value("Ouroboros_Min_Amount", @user.owner_id)
    MorLog.my_debug('Ouroboros payment : access', 1)
    MorLog.my_debug("Ouroboros payment : user - #{@user.id}", 1)
  end

  def ouroboros_pay
    #@user in before filter
    @page_title = _('Ouroboros')
    @page_icon = "money.png"
    @enabled = Confline.get_value("Ouroboros_Enabled", @user.owner_id).to_i
    MorLog.my_debug('Ouroboros payment : pay', 1)
    MorLog.my_debug("Ouroboros payment : user - #{@user.id}", 1)
    if @enabled == 1
      if params[:amount].to_d <= 0.0
        flash[:notice] = _('Enter_Payment_Amount')
        redirect_to :action => "ouroboros" and return false
      end
      @address = @user.address
      unless @address
        flash[:notice] = _('User_address_was_not_found')
        redirect_to :controller => "callc", :action => "main" and return false
      end

      @dir = @address.direction if  @address.direction_id.to_i > 0
      @direction = @dir.name if !@dir.nil?

      @merchant_code = Confline.get_value("Ouroboros_Merchant_Code", @user.owner_id)
      @lang = Confline.get_value("Ouroboros_Language", @user.owner_id)
      #@amount =            Confline.get_value("Ouronboros_Default_Amount", @user.owner_id).to_d
      @secret_key = Confline.get_value("Ouroboros_Secret_key", @user.owner_id)
      @ob_min_amount = Confline.get_value("Ouroboros_Min_Amount", @user.owner_id).to_d
      @ob_max_amount = Confline.get_value("Ouroboros_Max_Amount", @user.owner_id).to_d
      @currency = Confline.get_value('Ouroboros_Default_Currency', @user.owner_id)
      @retry_count = Confline.get_value("Ouroboros_Retry_Count", @user.owner_id)
      @completition = Confline.get_value("Ouroboros_Completion", @user.owner_id)
      @completition_over = Confline.get_value("Ouroboros_Completion_Over", @user.owner_id)
      @policy = OuroborosPayment.format_policy(@ob_max_amount, @retry_count, @completition, @completition_over)
      @amount = OuroborosPayment.format_amount(params[:amount], @ob_min_amount, @ob_max_amount)

      @ouroboros_return_url = Web_URL + Web_Dir + "/payments/ouroboros_result"
      @ouroboros_cancel_url = Web_URL + Web_Dir + "/callc/main"
      #@ouroboros_cancel_url = Web_URL + Web_Dir + "/payments/ouroboros_cancel"
      @ouroboros_accept_url = Web_URL + Web_Dir + "/payments/ouroboros_accept"
      @amount_with_vat = @user.get_tax.apply_tax(@amount)
      @description = session[:company] + " balance update"
      @payment = Payment.new
      @payment.paymenttype = 'ouroboros'
      @payment.amount = @amount_with_vat
      @payment.currency = @currency
      @payment.date_added = Time.now
      @payment.completed = 0
      @payment.gross = @amount
      @payment.first_name = session[:first_name]
      @payment.last_name = session[:last_name]
      @payment.tax = @amount_with_vat - @amount
      @payment.user_id = session[:user_id]
      @payment.pending_reason = 'Unnotified payment'
      @payment.owner_id = @user.owner_id
      @payment.save
      MorLog.my_debug("Ouroboros payment : payment - #{@payment.id}", 1) if @payment

    end
  end

  # /pay by gateway

=begin rdoc

=end

  def ouroboros_accept
    MorLog.my_debug('Ouroboros payment : accept', 1)
    @payment = Payment.find(:first, :conditions => "id = #{params[:order_id].to_i}")
    if @payment
      @user = @payment.user
      MorLog.my_debug("Ouroboros payment : user - #{@user.id}", 1)
      @enabled = Confline.get_value("Ouroboros_Enabled", @user.owner_id).to_i
      if @enabled.to_i == 1
        if @payment.pending_reason.to_s == 'Unnotified payment'
          key = Confline.get_value("Ouroboros_Secret_key", @user.owner_id)
          @hash = Ouroboros::Hash.reply_hash(params, key)
          if @hash == params[:signature]
            if params[:amount].to_d == @payment.amount.to_d*100
              @currency = Confline.get_value('Ouroboros_Default_Currency', @user.owner_id)
              rate = count_exchange_rate(session[:default_currency], @payment.currency)
              @user.balance += @payment.gross.to_d / rate
              @user.save
              @payment.completed = 1
              @payment.transaction_id = params[:tid]
              @payment.shipped_at = Time.now
              @payment.payer_email = @user.email
              @payment.payment_hash = params[:signature]
              @payment.pending_reason = ''
              @payment.save
              MorLog.my_debug("Ouroboros payment : payment - #{@payment.id}", 1) if @payment
              MorLog.my_debug("Ouroboros payment : amount - #{@payment.gross.to_d / rate}", 1)
              @error = 0
            else
              @error = 5
              MorLog.my_debug('Ouroboros payment : Amount missmach')
              MorLog.my_debug('   SYSTEM    :' + @payment.amount.to_s)
              MorLog.my_debug('   Ouroboros :' + (params[:amount].to_d/100).to_s)
            end
          else
            @error = 4
            MorLog.my_debug('Ouroboros payment : Hash missmach')
            MorLog.my_debug('   SYSTEM    :' + @hash)
            MorLog.my_debug('   Ouroboros :' + params[:signature])
          end
        else
          @error = 3
          MorLog.my_debug('Ouroboros payment : Unnotified payment.')
          MorLog.my_debug('   SYSTEM    : ' + @payment.pending_reason.to_s)
          MorLog.my_debug('   Ouroboros : Notified payment')
        end
      else
        @error = 2
        MorLog.my_debug('Ouroboros payment : Ouroboros disabled')
        MorLog.my_debug('   SYSTEM    : '+ @enabled.to_s)
      end
    else
      @error = 1
      MorLog.my_debug('Ouroboros payment : Payment was not found')
    end
  end

  ################# /Ouroboros ###################################################

  def change_description
    if @payment.owner_id == correct_owner_id
      @payment.description= params[:description]
      @payment.save
    end
    render :layout => false
  end


  private
  
  def safetypay_token(payment_id, amount, apikey, options = {})
	
	apiKey = apikey.to_s
	requestDateTime =  Time.now.iso8601.truncate(19, omission: '')	
	currencyID = options[:currency]
	amount = sprintf("%.2f", amount).to_s
	merchantSalesID = payment_id.to_s
	language = options[:language]
	transactionOkURL = options[:success_url]
	transactionErrorURL = options[:fail_url]
	customMerchantName = options[:company_name].to_s
	shopperEmail = options[:shopper_email]
	productID = "1"
	aPISignature = options[:safetypay_signature].to_s
    signature = Digest::SHA256.hexdigest(requestDateTime + currencyID + amount  + merchantSalesID + language + transactionOkURL + transactionErrorURL + aPISignature)
	
	message1 = { "ApiKey" => apiKey, "RequestDateTime"=> requestDateTime, "CurrencyID" => currencyID, "Amount" => amount, "MerchantSalesID" => merchantSalesID, "urn1:Language" => language, "TransactionOkURL" => transactionOkURL, "TransactionErrorURL" => transactionErrorURL, "CustomMerchantName" => customMerchantName, "ShopperEmail" => shopperEmail, "ProductID" => productID, "Signature"=> signature  }
	
	if options[:test].to_i == 1
		client = Savon.client(wsdl: "/home/mor/public/safetypay/MerchantExpressWs.wsdl", namespaces: {"xmlns:urn" => "urn:safetypay:messages:mws:api",   "xmlns:urn1"  =>"urn:safetypay:schema:mws:api"}, namespace_identifier: :urn, env_namespace: :soapenv, convert_request_keys_to: :none)
	else
	#  Set the client for production here.	
		client = Savon.client(wsdl: "/home/mor/public/safetypay/MerchantExpressWs_prod.wsdl", namespaces: {"xmlns:urn" => "urn:safetypay:messages:mws:api",   "xmlns:urn1"  =>"urn:safetypay:schema:mws:api"}, namespace_identifier: :urn, env_namespace: :soapenv, convert_request_keys_to: :none)
	end
	
	response = client.call(:create_express_token, message_tag: :ExpressTokenRequest, message: message1 )
	if response.success? == true
		response = response.body
		data = response[:express_token_response]
		
		if data[:error_manager][:error_number].to_i == 0
			url_token = data[:shopper_redirect_url]
		else
			MorLog.my_debug("SafetyPay. Error in response: #{data[:error_manager][:description].to_s}. #{message1}")
			url_token = nil
		end
	else
		MorLog.my_debug('SafetyPay. No response from client call')
		url_token = nil
	end
	
	return url_token	
	
  end
  def mercadopago_token(client_id, client_secret, options = {})
	
	url_token = nil
	mp = MercadoPago.new(client_id, client_secret)
	
	preferenceData = {"items" => ["id" => options[:payment_id], "title"=>_("MercadoPago_Title"), "category_id" => "virtual_goods", "quantity"=>1, "unit_price"=>options[:amount], "currency_id"=>options[:currency]], "payer" => {"name" => options[:payer_name], "surname" => options[:payer_surname], "email" => options[:payer_email]}, "back_urls" => {"success" => options[:success_url], "pending" => options[:pending_url], "failure" => options[:failure_url]}, "marketplace" => options[:marketplace], "external_reference" => options[:payment_id].to_s + "*" + options[:user_id].to_s, "notification_url" => options[:notification_url]}
	preference = mp.create_preference(preferenceData)
	
	if (preference['status'] == "200" or preference['status'] == "201")
			url_token = preference['response']['init_point']
		if options[:test].to_i == 1 #Url for testing
			url_token = url_token.gsub("https://www", "https://sandbox")
		end
	else
		MorLog.my_debug('MercadoPago. Preference not created')
	end
	
	return url_token
	
  end

  def find_user_session
    @user = User.find(:first, :include => [:tax], :conditions => ["users.id = ?", session[:user_id]])

    unless @user
      flash[:notice] = _('User_was_not_found')
      redirect_to :controller => :callc, :action => :main
    end
  end

  def find_payment
    @payment = Payment.where(:id => params[:id]).first

    unless @payment
      flash[:notice] = _('Payment_was_not_found')
      redirect_to :controller => :callc, :action => :main
    end
  end

=begin rdoc
 Santitizes params for sql input.
=end

  def get_price_exchange(price, cur)
    exrate = Currency.count_exchange_rate(cur, current_user.currency.name)
    rate_cur = Currency.count_exchange_prices({:exrate => exrate, :prices => [price.to_d]})
    return rate_cur.to_d
  end
end