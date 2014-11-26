###############################################################
# $Id$
#
#  72_FRITZBOX.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module handles the Fritz!Phone MT-F 
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> FRITZBOX
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;


sub FRITZBOX_Log($$$);
sub FRITZBOX_Init($);
sub FRITZBOX_Init_Reading($$$@);
sub FRITZBOX_Ring($@);
sub FRITZBOX_Exec($$);
  
my %fonModel = ( 
        '0x01' => "MT-D"
      , '0x03' => "MT-F"
      , '0x04' => "C3"
      , '0x05' => "C4"
      , '0x08' => "M2"
   );

my %ringTone = ( 
     0 => "HandsetDefault"
   , 1 => "HandsetInternalTon"
   , 2 => "HandsetExternalTon"
   , 3 => "Standard"
   , 4 => "Eighties"
   , 5 => "Alert"
   , 6 => "Ring"
   , 7 => "RingRing"
   , 8 => "News"
   , 9 => "CustomerRingTon"
   , 10 => "Bamboo"
   , 11 => "Andante"
   , 12 => "ChaCha"
   , 13 => "Budapest"
   , 14 => "Asia"
   , 15 => "Kullabaloo"
   , 16 => "silent"
   , 17 => "Comedy"
   , 18 => "Funky",
   , 19 => "Fatboy"
   , 20 => "Calypso"
   , 21 => "Pingpong"
   , 22 => "Melodica"
   , 23 => "Minimal"
   , 24 => "Signal"
   , 25 => "Blok1"
   , 26 => "Musicbox"
   , 27 => "Blok2"
   , 28 => "2Jazz"
   , 33 => "InternetRadio"
   , 34 => "MusicList"
   );

my %ringToneNumber;
while (my ($key, $value) = each %ringTone) {
   $ringToneNumber{lc $value}=$key;
}

my %alarmDays = ( 
     1 => "Mo"
   , 2 => "Tu"
   , 4 => "We"
   , 8 => "Th"
   , 16 => "Fr"
   , 32 => "Sa"
   , 64 => "So"
);
   
my @radio = ();

sub ##########################################
FRITZBOX_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZBOX_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "FRITZBOX $instName: $sub.$xline " . $text;
}

sub ##########################################
FRITZBOX_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRITZBOX_Define";
  $hash->{UndefFn}  = "FRITZBOX_Undefine";

  $hash->{SetFn}    = "FRITZBOX_Set";
  $hash->{GetFn}    = "FRITZBOX_Get";
  $hash->{AttrFn}   = "FRITZBOX_Attr";
  $hash->{AttrList} = "disable:0,1 "
                ."ringWithIntern:0,1,2 "
                ."defaultCallerName "
                ."defaultUploadDir "
                .$readingFnAttributes;

} # end FRITZBOX_Initialize


sub ##########################################
FRITZBOX_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Usage: define <name> FRITZBOX" if(@args <2 || @args >2);  

   my $name = $args[0];

   $hash->{NAME} = $name;

   $hash->{STATE}       = "Initializing";
   $hash->{Message}     = "FHEM";
   $hash->{fhem}{modulVersion} = '$Date$';

   RemoveInternalTimer($hash);
 # Get first data after 6 seconds
   InternalTimer(gettimeofday() + 6, "FRITZBOX_Init", $hash, 0);
 
   return undef;
} #end FRITZBOX_Define


sub ##########################################
FRITZBOX_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  return undef;
} # end FRITZBOX_Undefine


sub ##########################################
FRITZBOX_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value
   my $hash = $defs{$name};

   if ($cmd eq "set")
   {
   }

   return undef;
} # FRITZBOX_Attr ende


sub ##########################################
FRITZBOX_Set($$@) 
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";
   
   my $list = "update:noArg"
            . " customerRingTone"
            . " convertRingTone"
            . " guestWlan:on,off"
            . " message"
            . " ring"
            . " startRadio"
            . " wlan:on,off";

   if ( lc $cmd eq 'convertringtone')
   {
      if (int @val > 0) 
      {
         return FRITZBOX_ConvertRingTone $hash, @val;
      }
   }
   elsif ( lc $cmd eq 'customerringtone')
   {
      if (int @val > 0) 
      {
         return FRITZBOX_SetCustomerRingTone $hash, @val;
      }
   }
   elsif ( lc $cmd eq 'message')
   {
      if (int @val > 0) 
      {
         $hash->{Message} = substr (join(" ", @val),0,30) ;
         return undef;
      }
   }
   elsif ( lc $cmd eq 'ring')
   {
      if (int @val > 0) 
      {
         FRITZBOX_Ring $hash, @val;
         return undef;
      }
   }
   elsif( lc $cmd eq 'update' ) 
   {
      FRITZBOX_Init($hash);
      return undef;
   }
   elsif ( lc $cmd eq 'startradio')
   {
      if (int @val > 0) 
      {
         # FRITZBOX_Ring $hash, @val; # join("|", @val);
         return undef;
      }
   }
   elsif ( lc $cmd eq 'wlan')
   {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) 
      {
         $val[0] =~ s/on/1/;
         $val[0] =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w wlan settings/ap_enabled $val[0]");
         return undef;
      }
   }
   elsif ( lc $cmd eq 'guestwlan')
   {
      if (int @val == 1 && $val[0] =~ /^(on|off)$/) 
      {
         $val[0] =~ s/on/1/;
         $val[0] =~ s/off/0/;
         FRITZBOX_Exec( $hash, "ctlmgr_ctl w wlan settings/guest_ap_enabled $val[0]");
         return undef;
      }
   }

   return "Unknown argument $cmd or wrong parameter, choose one of $list";

} # end FRITZBOX_Set


sub ##########################################
FRITZBOX_Get($@)
{
   my ($hash, $name, $cmd) = @_;
   my $returnStr;

   if (lc $cmd eq "ringtones") 
   {
      $returnStr  = "Ring tones to use with 'set <name> ring <intern> <duration> <ringTone>'\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      $returnStr .= join "\n", sort values %ringTone;
      return $returnStr;
   }

   my $list = "ringTones:noArg";
   return "Unknown argument $cmd, choose one of $list";
} # end FRITZBOX_Get


# Starts the data capturing and sets the new timer
sub ##########################################
FRITZBOX_Init($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $result;
   my $rName;
   my @cmdArray;
   my @readoutArray;
   my $resultArray;
   
   FRITZBOX_Log $hash, 4, "Start update of device readings.";
   readingsBeginUpdate($hash);

  # Box Firmware
   push @readoutArray, [ "box_fwVersion", "ctlmgr_ctl r logic status/nspver", "fwupdate" ];
  # WLAN
   push @readoutArray, [ "box_wlan", "ctlmgr_ctl r wlan settings/ap_enabled", "onoff" ];
  # G�ste WLAN
   push @readoutArray, [ "box_guestWlan", "ctlmgr_ctl r wlan settings/guest_ap_enabled", "onoff" ];
   FRITZBOX_Array_Readout( $hash, \@readoutArray );
   
  # Internetradioliste erzeugen
   my $i = 0;
   @radio = ();
   $rName = "radio00";
   do 
   {
      $result = FRITZBOX_Init_Reading($hash 
         , $rName
         , "ctlmgr_ctl r configd settings/WEBRADIO".$i."/Name");
      push (@radio, $result)
         if $result;
      $i++;
      $rName = sprintf ("radio%02d",$i);
   }
   while ( $result ne "" || defined $hash->{READINGS}{$rName} );

# Dect Telefon
   foreach (610..615) { delete $hash->{fhem}{$_} if defined $hash->{fhem}{$_}; }
   
   # Init Foncontrol
   FRITZBOX_Exec ($hash, "ctlmgr_ctl r telcfg settings/Foncontrol");
   foreach (1..6)
   {
     # Dect-Interne Nummer
      my $intern = FRITZBOX_Init_Reading($hash, 
         "dect".$_."_intern", 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Intern");
      next 
         unless $intern ne "";
     # Dect-Telefonname
      $result = FRITZBOX_Init_Reading($hash, 
         "dect".$_, 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Name");
      $hash->{fhem}{$intern}{name} = $result;
     # Handset manufacturer
      $result = FRITZBOX_Init_Reading($hash, 
         "dect".$_."_manufacturer", 
         "ctlmgr_ctl r dect settings/Handset".($_-1)."/Manufacturer");   
      $hash->{fhem}{$intern}{brand} = $result;
      if ($result eq "AVM")
      {
        # Internal Ring Tone Name
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_intRingTone"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/IntRingTone"
            , "ringtone");
        # Alarm Ring Tone Name
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_alarmRingTone"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/AlarmRingTone0"
            , "ringtone");
        # Radio Name
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_radio"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/RadioRingID"
            , "radio");
        # Background image
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_imagePath "
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/ImagePath ");
        # Customer Ring Tone
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_custRingTone"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingTone");
        # Customer Ring Tone Name
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_custRingToneName"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingToneName");
        # Firmware Version
         FRITZBOX_Init_Reading($hash
            , "dect".$_."_fwVersion"
            , "ctlmgr_ctl r dect settings/Handset".($_-1)."/FWVersion");   
        # Phone Model
         $result = FRITZBOX_Init_Reading($hash 
            , "dect".$_."_model"
            , "ctlmgr_ctl r dect settings/Handset".($_-1)."/Model"
            , "model");   
         $hash->{fhem}{$intern}{model} = $result;
      }
   }

# Analog telefons
   foreach (1..3)
   {
      push @readoutArray, ["fon".$_, "ctlmgr_ctl r telcfg settings/MSN/Port".($_-1)."/Name"];
   }

# Alarm clock
   foreach (0..2)
   {
     # Alarm clock name
      push @readoutArray, ["alarm".($_+1), "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Name"];
     # Alarm clock state
      push @readoutArray, ["alarm".($_+1)."_state", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Active", "onoff"];
     # Alarm clock time
      push @readoutArray, ["alarm".($_+1)."_time", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Time", "altime"];
     # Alarm clock number
      push @readoutArray, ["alarm".($_+1)."_target", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Number", "alnumber"];
     # Alarm clock weekdays
      push @readoutArray, ["alarm".($_+1)."_wdays", "ctlmgr_ctl r telcfg settings/AlarmClock".$_."/Weekdays", "aldays"];
   }
   $resultArray = FRITZBOX_Array_Readout( $hash, \@readoutArray );
# Analog telefons number
   foreach (1..3)
   {
      readingsBulkUpdate($hash, "fon".$_."_intern", $_)
         if $resultArray->[$_-1];
   }
   
# user profiles
   $i=0;
   $rName = "user01";
   do 
   {
      push @readoutArray, [$rName, "ctlmgr_ctl r user settings/user".$i."/name"];
      push @readoutArray, [$rName."_thisMonthTime", "ctlmgr_ctl r user settings/user".$i."/this_month_time", "timeinhours"];
      push @readoutArray, [$rName."_todayTime", "ctlmgr_ctl r user settings/user".$i."/today_time", "timeinhours"];
      push @readoutArray, [$rName."_type", "ctlmgr_ctl r user settings/user".$i."/type"];
      $resultArray = FRITZBOX_Array_Readout( $hash, \@readoutArray );
      $i++;
      $rName = sprintf ("user%02d",$i+1);
   }
   while ($i<100 && ($resultArray->[0] ne "" || defined $hash->{READINGS}{$rName} ));
   
   readingsEndUpdate( $hash, 1 );
   FRITZBOX_Log $hash, 4, "Update of device readings finished.";

   RemoveInternalTimer($hash);
 # Get next data after 15 minutes
   InternalTimer(gettimeofday() + 900, "FRITZBOX_Init", $hash, 1);
   
}

sub ##########################################
FRITZBOX_Init_Reading($$$@)
{
   my ($hash, $rName, $cmd, $rFormat) = @_;
   
   $rFormat = "" 
      unless defined $rFormat;
   
   my $rValue = FRITZBOX_Exec( $hash, $cmd);
   
   $rValue = FRITZBOX_Format_Readout( $hash, $rFormat, $rValue );
   if ($rValue)
   {
      readingsBulkUpdate($hash, $rName, $rValue)
   } 
   elsif (defined $hash->{READINGS}{$rName} ) 
   {
      delete $hash->{READINGS}{$rName};
   }
   return $rValue;
}

sub ##########################################
FRITZBOX_Array_Readout($$)
{
   my ($hash, $readoutArray) = @_;
   my @cmdArray;
   my $rValue;
   my $rName;
   my $rFormat;
      
   my $count = int @{$readoutArray} -1;
   for (0..$count)
   {
      push @cmdArray, $readoutArray->[$_][1];
   }
   
   my $resultArray = FRITZBOX_Exec( $hash, \@cmdArray);
   $count = int @{$resultArray} -1;
   for (0..$count)
   {
      $rValue = $resultArray->[$_];
      $rFormat = $readoutArray->[$_][2];
      $rFormat = "" unless defined $rFormat;
      $rValue = FRITZBOX_Format_Readout ($hash, $rFormat, $rValue);
      $rName = $readoutArray->[$_][0];
      if ($rValue ne "")
      {
         FRITZBOX_Log $hash, 5, "$rName: $rValue";
         readingsBulkUpdate($hash, $rName, $rValue);
      }
      elsif (defined $hash->{READINGS}{$rName} ) 
      {
         FRITZBOX_Log $hash, 5, "Delete $rName";
         delete $hash->{READINGS}{$rName};
      }
   }
   @{$readoutArray} = ();
   
   return $resultArray;
}

sub ##########################################
FRITZBOX_Format_Readout($$$) 
{
   my ($hash, $format, $readout) = @_;
   
   return $readout 
      unless $readout ne "" && $format ne "" ;

   if ($format eq "altime") {
      $readout =~ s/(\d\d)(\d\d)/$1:$2/;
   } elsif ($format eq "aldays") {
      if ($readout == 0) {
         $readout = "once";
      } elsif ($readout == 127) {
         $readout = "daily";
      } else {
         my $bitStr = $readout;
         $readout = "";
         foreach (sort keys %alarmDays)
         {
            $readout .= (($bitStr & $_) == $_) ? $alarmDays{$_}." " : "";
         }
      }
   } elsif ($format eq "alnumber") {
      if (60 <= $readout && $readout <=65) {
         my $intern = $readout + 550;
         $readout = $hash->{fhem}{$intern}{name}." - DECT $intern";
      } elsif ($readout == 9) {
         $readout = "all DECT";
      } elsif ($readout == 50) {
         $readout = "all";
      }
   } elsif ($format eq "fwupdate") {
      my $update = FRITZBOX_Exec( $hash, "ctlmgr_ctl r updatecheck status/update_available_hint");
      $readout .= " (old)" if $update == 1;
   } elsif ($format eq "model") {
      $readout = $fonModel{$readout} if defined $fonModel{$readout};
   
   } elsif ($format eq "onoff") {
      $readout =~ s/0/off/;
      $readout =~ s/1/on/;
   
   } elsif ($format eq "radio") {
      $readout = $radio[$readout];
   
   } elsif ($format eq "ringtone") {
      $readout = $ringTone{$readout};
   
   } elsif ($format eq "timeinhours") {
      $readout = sprintf "%d h %d min", int $readout/3600, int( ($readout %3600) / 60);
   }
   return $readout;
}
   
sub ##########################################
FRITZBOX_Ring($@) 
{
   my ($hash, @val) = @_;
   my $name = $hash->{NAME};
   
   $val[1] = 5 
      unless defined $val[1]; 

   if ( exists( $hash->{helper}{RUNNING_PID} ) )
   {
      FRITZBOX_Log $hash, 1, "Old process still running. Killing old process ".$hash->{helper}{RUNNING_PID};
      BlockingKill( $hash->{helper}{RUNNING_PID} ); 
      delete($hash->{helper}{RUNNING_PID});
   }
   
   my $timeout = $val[1] + 30;
   my $handover = $name . "|" . join( "|", @val );
   
   $hash->{helper}{RUNNING_PID} = BlockingCall("FRITZBOX_Ring_Run", $handover,
                                       "FRITZBOX_Ring_Done", $timeout,
                                       "FRITZBOX_Ring_Aborted", $hash)
                              unless exists $hash->{helper}{RUNNING_PID};
} # end FRITZBOX_Ring

sub ##########################################
FRITZBOX_Ring_Run($) 
{
   my ($string) = @_;
   my ($name, @val) = split /\|/, $string;
   my $hash = $defs{$name};
   
   my $fonType;
   my $fonTypeNo;
   my $result;
   my $curIntRingTone;
   my $curCallerName;
   my $cmd;
   my @cmdArray;

   my $intNo;
   $intNo = $val[0]
      if $val[0] =~ /^\d+$/;
   return $name."|0|Error: Parameter '".$val[0]."' not a number"
      unless defined $intNo;
   shift @val;
   
   $fonType = $hash->{fhem}{$intNo}{brand};
   return $name."|0|Error: Internal number '$intNo' not a DECT number" 
      unless defined $fonType;
   $fonTypeNo = $intNo - 609;
   
   
   my $duration = 5;
   if ($val[0] !~ /^msg:/i)
   {
      $duration = $val[0]
         if defined $val[0];
      shift @val;
      return $name."|0|Error: Duration '".$val[0]."' not a positiv integer" 
         unless $duration =~ /^\d+$/;
   }
   
   my $ringTone;
   if ($val[0] !~ /^msg:/i)
   {
      $ringTone = $val[0]
         unless $fonType ne "AVM";
      if (defined $ringTone)
      {
         $ringTone = $ringToneNumber{lc $val[0]};
         return $name."|0|Error: Ring tone '".$val[0]."' not valid"
            unless defined $ringTone;
      }
      shift @val;
   }
      
   my $msg = AttrVal( $name, "defaultCallerName", "FHEM" );
   if (int @val > 0)
   {
      return $name."|0|Error: Too many parameter. Message has to start with 'msg:'"
         if ($val[0] !~ /^msg:/i);
      $msg = join " ", @val;
      $msg =~ s/^msg:\s*//;
      $msg = substr($msg, 0, 30);
   }


#Preparing 1st command array
   @cmdArray = ();
# Change ring tone of Fritz!Fons
   if (defined $ringTone)
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$ringTone;
      FRITZBOX_Log $hash, 4, "Change temporarily internal ring tone of DECT ".$fonTypeNo." to ".$ringTone;
   }

# uses name of virtual port 0 (dial port 1) to show message on ringing phone
   my $ringWithIntern = AttrVal( $name, "ringWithIntern", 0 );
   if ($ringWithIntern =~ /^(1|2)$/ )
   {
      push @cmdArray, "ctlmgr_ctl r telcfg settings/MSN/Port".($ringWithIntern-1)."/Name";
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$msg'";
      FRITZBOX_Log $hash, 4, "Change temporarily name of calling number $ringWithIntern to '$msg'";
   }
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort ".$ringWithIntern
      if $ringWithIntern != 0 ;
   $result = FRITZBOX_Exec( $hash, \@cmdArray )
      if @cmdArray > 0;

#Preparing 2nd command array to ring and reset everything
   FRITZBOX_Log $hash, 4, "Ringing $intNo for $duration seconds";
   push @cmdArray, "ctlmgr_ctl w telcfg command/Dial **".$intNo;
   push @cmdArray, "sleep ".($duration+1);
   push @cmdArray, "ctlmgr_ctl w telcfg command/Hangup **".$intNo;
   push @cmdArray, "ctlmgr_ctl w telcfg settings/DialPort 50"
      if $ringWithIntern != 0 ;
   if (defined $ringTone)
   {
      push @cmdArray, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$result->[0];
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[2]."'"
         if $ringWithIntern =~ /^(1|2)$/;
   }
   elsif ($ringWithIntern =~ /^(1|2)$/)
   {
      push @cmdArray, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '".$result->[0]."'";
   }
   FRITZBOX_Exec( $hash, \@cmdArray );

   return $name."|1|Ringing done";
}

sub ##########################################
FRITZBOX_Ring_Done($) 
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, $success, $result) = split("\\|", $string);
   my $hash = $defs{$name};
   
   delete($hash->{helper}{RUNNING_PID});

   if ($success != 1)
   {
      FRITZBOX_Log $hash, 1, $result;
   }
   else
   {
      FRITZBOX_Log $hash, 4, $result;
   }
}

sub ##########################################
FRITZBOX_Ring_Aborted($) 
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  FRITZBOX_Log $hash, 1, "Timeout when ringing";
}

sub ############################################
FRITZBOX_SetCustomerRingTone($@)
{  
   my ($hash, $intern, @file) = @_;
   my $returnStr;
   my $name = $hash->{NAME};

   my $uploadDir = AttrVal( $name, "defaultUploadDir",  "" );
   $uploadDir .= "/"
      unless $uploadDir =~ /\/$|^$/;

   my $inFile = join " ", @file;
   $inFile = $uploadDir.$inFile
      unless $inFile =~ /^\//;
   
   return "Error: Please give a complete file path or the attribute 'defaultUploadDir'"
      unless $inFile =~ /^\//;
   
   return "Error: Only MP3 or G722 files can be uploaded to the phone."
      unless $inFile =~ /\.mp3$|.g722$/i;
   
   my $uploadFile = '/var/InternerSpeicher/FRITZ/fonring/'.time().'.g722';
   
   $inFile =~ s/file:\/\///i;
   if ( $inFile =~ /\.mp3$/i )
   {
      # mp3 files are converted
      $returnStr = FRITZBOX_Exec ($hash
      , 'picconv.sh "file://'.$inFile.'" "'.$uploadFile.'" ringtonemp3');
   }
   elsif ( $inFile =~ /\.g722$/i )
   {
      # G722 files are copied
      $returnStr = FRITZBOX_Exec ($hash,
         "cp '$inFile' '$uploadFile'");
   }
   else
   {
      return "Error: only MP3 or G722 files can be uploaded to the phone";
   }
   # trigger the loading of the file to the phone, file will be deleted as soon as the upload finished
   $returnStr .= "\n".FRITZBOX_Exec ($hash,
      '/usr/bin/pbd --set-ringtone-url --book="255" --id="'.$intern.'" --url="file://'.$uploadFile.'" --name="FHEM'.time().'"');
   return $returnStr;
}

sub ############################################
FRITZBOX_ConvertRingTone ($@)
{  
   my ($hash, @file) = @_;

   my $name = $hash->{NAME};

   my $uploadDir = AttrVal( $name, "defaultUploadDir",  "" );
   $uploadDir .= "/"
      unless $uploadDir =~ /\/$|^$/;

   my $inFile = join " ", @file;
   $inFile = $uploadDir.$inFile
      unless $inFile =~ /^\//;
   
   return "Error: You have to give a complete file path or to set the attribute 'defaultUploadDir'"
      unless $inFile =~ /^\//;
   
   return "Error: only MP3 or WAV files can be converted"
      unless $inFile =~ /\.mp3$|.wav$/i;
   
   $inFile =~ s/file:\/\///;

   my $outFile = $inFile;
   $outFile = substr($inFile,0,-4)
      if ($inFile =~ /\.(mp3|wav)$/i);
   my $returnStr = FRITZBOX_Exec ($hash
      , 'picconv.sh "file://'.$inFile.'" "'.$outFile.'.g722" ringtonemp3');
   return $returnStr;
   
#'picconv.sh "'.$inFile.'" "'.$outFile.'.g722" ringtonemp3'
#picconv.sh "file://$dir/upload.mp3" "$dir/$filename" ringtonemp3   
#"ffmpegconv  -i '$inFile' -o '$outFile.g722' --limit 240");
#ffmpegconv -i "${in}" -o "${out}" --limit 240
#pbd --set-image-url --book=255 --id=612 --url=/var/InternerSpeicher/FRITZ/fonring/1416431162.g722 --type=1
#pbd --set-image-url --book=255 --id=612 --url=file://var/InternerSpeicher/FRITZBOXtest.g722 --type=1
#ctlmgr_ctl r user settings/user0/bpjm_filter_enable
#/usr/bin/pbd --set-ringtone-url --book="255" --id="612" --url="file:///var/InternerSpeicher/claydermann.g722" --name="Claydermann"
}


# Executed the command on the FritzBox Shell
sub ############################################
FRITZBOX_Exec($$)
{
   my ($hash, $cmd) = @_;
   
   if (ref \$cmd eq "SCALAR")
   {
      FRITZBOX_Log $hash, 5, "Execute '".$cmd."'";
      my $result = qx($cmd);
      chomp $result;
      FRITZBOX_Log $hash, 5, "Result '$result'";
      return $result;
   }
   elsif (ref \$cmd eq "REF")
   {
      if (int @{$cmd} >0 )
      {
         FRITZBOX_Log $hash, 5, "Execute '".(join " | ", @{$cmd})."'";
         my $cmdStr = join "\necho ' |#|'\n", @{$cmd};
         $cmdStr .= "\necho ' |#|'";
         my $result = qx($cmdStr);
         $result =~ s/\n|\r//g;
         my @resultArray = split /\|#\|/, $result;
         foreach (keys @resultArray)
         { 
            $resultArray[$_] =~ s/\s$//;
         }
         @{$cmd} = ();
         FRITZBOX_Log $hash, 5, "Result '".join (" | ", @resultArray)."' (count: ".int (@resultArray).")";
         return \@resultArray;
      }
   }
}

##################################### 

1;

=pod
=begin html

<a name="FRITZBOX"></a>
<h3>FRITZBOX</h3>
<div  style="width:800px"> 
<ul>
   Controls some features of a Fritz!Box router. Connected Fritz!Fon's (MT-F, MT-D, C3, C4) can be used as signaling devices.
   <br>
   Note!! To use it, FHEM has to run on a Fritz!Box.
   <br/><br/>
   <a name="FRITZBOXdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZBOX</code>
      <br>
      Example:
      <br>
      <code>define fritzbox FRITZBOX</code>
      <br/><br/>
   </ul>
  
   <a name="FRITZBOXset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; guestWLAN &lt;on|off&gt;</code>
         <br>
         Switches the guest WLAN on or off.
      </li><br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Starts an update of the device readings.
      </li><br>
      <li><code>set &lt;name&gt; ring &lt;internalNumber&gt; [duration [ringTone]] [msg:yourMessage]</code>
         Example: <code>set fritzbox ring 612 5 Budapest msg:It is raining</code>
         <br>
         Rings the internal number for "duration" seconds with the given "ring tone" name.
         <br>
         The text in msg() will be shown as the callers name. 
         Maximal 30 characters are allowed.
         The attribute "ringWithIntern" must also be specified.
         <br>
         Default duration is 5 seconds. Default ring tone is the internal ring tone of the device.
      </li><br>
      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;fullFilePath&gt;</code>
         <br>
         Uploads the file fullFilePath on the given handset. Only mp3 or G722 format is allowed.
         <br>
         The file has to be placed on the file system of the fritzbox.
         <br>
         The upload takes about one minute before the tone is available.
      </li><br>
      <li><code>set &lt;name&gt; startradio &lt;internalNumber&gt; [name]</code>
         <br>
         not implemented yet. Start the internet radio on the given Fritz!Fon
         <br>
      </li><br>
      <li><code>set &lt;name&gt; wlan &lt;on|off&gt;</code>
         <br>
         Switches WLAN on or off.
      </li><br>
   </ul>  

   <a name="FRITZBOXget"></a>
   <b>Get</b>
   <ul>
      <li><code>get &lt;name&gt; ringTones</code>
         <br>
         Shows a list of ring tones that can be used.
      </li><br>
   </ul>  
  
   <a name="FRITZBOXattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>defaultCallerName</code>
         <br>
         The default text to show on the ringing phone as 'caller'.
         <br>
         This is done by temporarily changing the name of the calling internal number during the ring.
         <br>
         Maximal 30 characters are allowed. The attribute "ringWithIntern" must also be specified.
      </li><br>
      <li><code>ringWithIntern &lt;internalNumber&gt;</code>
         <br>
         To ring a fon a caller must always be specified. Default of this modul is 50 "ISDN:W&auml;hlhilfe".
         <br>
         To show a message (default is "FHEM") during a ring the internal phone numbers 1 or 2 can be specified here.
      </li><br>
      <li><code>defaultUploadDir &lt;fritzBoxPath&gt;</code>
         <br>
         This is the default path that will be used if a file name does not start with / (slash).
         <br>
         It needs to be the name of the path on the Fritz!Box, so it should start with /var/InternerSpeicher if it equals in windows \\ip-address\fritz.nas
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="FRITZBOXreading"></a>
   <b>Readings</b>
   <ul><br>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Internal ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Internal number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Manufacturer of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_name</b> - Internal name of the DECT device <i>1</i></li>
   </ul>
   <br>
</ul>
</div>

=end html

=cut