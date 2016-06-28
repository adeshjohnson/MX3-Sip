# -*- encoding : utf-8 -*-
# Load the rails application
require File.expand_path('../application', __FILE__)
Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

# Initialize the rails application
Mor::Application.initialize!

#---------------
ExceptionNotifier_exception_recipients = %w(soporte@fututel.com)
ExceptionNotifier_email_prefix="[GAMJOM.sip]"

Default_Language = "en"
#---------------

Debug_File = "/tmp/mor_debug.log"

Please_Login_Context = "please_login"
Default_Context = "mor"

Recordings_Folder="http://sip.fututel.com/billing/recordings/"

Actual_Dir = "/home/mor"
Web_Dir = Rails.env.to_s == 'production' ? "/billing" : ''
Web_URL = "http://sip.fututel.com"

Main_User_ID = 0

# ------- Functionality ------

F_BACKUPS = 0

# --------- ADDONS ---------

CC_Active = 1   
CC_Single_Login = 0 
AD_Active = 1    
AD_sounds_path = "/var/lib/asterisk/sounds/mor/ad"
RS_Active = 1    
SMS_Active = 1   
REC_Active = 1   
PG_Active = 1    
CS_Active = 1   
MA_Active = 1    
AST_18 = 1       
PROVB_Active = 1 
RSPRO_Active = 1 
CALLB_Active = 1 
