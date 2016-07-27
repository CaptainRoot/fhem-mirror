# $Id$
##############################################################################
#
#     98_GEOFANCY.pm
#     An FHEM Perl module to receive geofencing webhooks from geofancy.com.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     Based on HTTPSRV from Dr. Boris Neubert
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Time::Local;
use Data::Dumper;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

sub GEOFANCY_Set($@);
sub GEOFANCY_Define($$);
sub GEOFANCY_Undefine($$);

#########################
sub GEOFANCY_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 2, "Registering GEOFANCY $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

#########################
sub GEOFANCY_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2, "Unregistering GEOFANCY $name for URL $url...";
    delete $data{FWEXT}{$url};
}

###################################
sub GEOFANCY_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "GEOFANCY_Initialize: Entering";

    $hash->{SetFn}    = "GEOFANCY_Set";
    $hash->{DefFn}    = "GEOFANCY_Define";
    $hash->{UndefFn}  = "GEOFANCY_Undefine";
    $hash->{AttrList} = "devAlias " . $readingFnAttributes;
}

###################################
sub GEOFANCY_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> GEOFANCY <infix>"
      if ( int(@a) != 3 );
    my $name  = $a[0];
    my $infix = $a[2];

    $hash->{fhem}{infix} = $infix;

    GEOFANCY_addExtension( $name, "GEOFANCY_CGI", $infix );

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", "initialized" );
    readingsEndUpdate( $hash, 1 );
    return undef;
}

###################################
sub GEOFANCY_Undefine($$) {

    my ( $hash, $name ) = @_;

    GEOFANCY_removeExtension( $hash->{fhem}{infix} );

    return undef;
}

###################################
sub GEOFANCY_Set($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};

    Log3 $name, 5, "GEOFANCY $name: called function GEOFANCY_Set()";

    return "No Argument given" if ( !defined( $a[1] ) );

    my $usage = "Unknown argument " . $a[1] . ", choose one of clear:readings";

    # clear
    if ( $a[1] eq "clear" ) {
        Log3 $name, 2, "GEOFANCY set $name " . $a[1];

        if ( $a[2] ) {

            # readings
            if ( $a[2] eq "readings" ) {
                delete $hash->{READINGS};
                readingsBeginUpdate($hash);
                readingsBulkUpdate( $hash, "state", "clearedReadings" );
                readingsEndUpdate( $hash, 1 );
            }

        }

        else {
            return "No Argument given, choose one of readings ";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub GEOFANCY_CGI() {

# Locative.app (https://itunes.apple.com/us/app/locative/id725198453?mt=8)
# /$infix?device=UUIDdev&id=UUIDloc&latitude=xx.x&longitude=xx.x&trigger=(enter|exit)
#
# Geofency.app (https://itunes.apple.com/us/app/geofency-time-tracking-automatic/id615538630?mt=8)
# /$infix?id=UUIDloc&name=locName&entry=(1|0)&date=DATE&latitude=xx.x&longitude=xx.x&device=UUIDdev
#
# SMART Geofences.app (https://www.microsoft.com/en-us/store/apps/smart-geofences/9nblggh4rk3k)
# /$infix?device=UUIDdev&name=UUIDloc&latitude=xx.x&longitude=xx.x&type=(Entered|Leaving)&date=DATE
#
    my ($request) = @_;

    my $hash;
    my $name        = "";
    my $link        = "";
    my $URI         = "";
    my $device      = "";
    my $deviceAlias = "-";
    my $id          = "";
    my $lat         = "";
    my $long        = "";
    my $address     = "-";
    my $entry       = "";
    my $msg         = "";
    my $date        = "";
    my $time        = "";
    my $locName     = "";

    # data received
    if ( $request =~ m,^(\/[^/]+?)(?:\&|\?|\/\?|\/)(.*)?$, ) {
        $link = $1;
        $URI  = $2;

        # get device name
        $name = $data{FWEXT}{$link}{deviceName} if ( $data{FWEXT}{$link} );

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "NOK No GEOFANCY device for webhook $link" )
          unless ($name);

        # extract values from URI
        my $webArgs;
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = $v;
        }

        # validate id
        # does not exist in "SMART Geofences.app"
        return ( "text/plain; charset=utf-8",
            "NOK Expected value for 'id' cannot be empty" )
          if ( ( !defined( $webArgs->{id} ) || $webArgs->{id} eq "" )
            && !defined( $webArgs->{type} ) );

        return ( "text/plain; charset=utf-8",
            "NOK No whitespace allowed in id '" . $webArgs->{id} . "'" )
          if ( defined( $webArgs->{id} ) && $webArgs->{id} =~ m/(?:\s)/ );

        # validate locName
        return ( "text/plain; charset=utf-8",
            "NOK No whitespace allowed in id '" . $webArgs->{locName} . "'" )
          if ( defined( $webArgs->{locName} )
            && $webArgs->{locName} =~ m/(?:\s)/ );

        # require entry or trigger
        return ( "text/plain; charset=utf-8",
            "NOK Neither 'entry' nor 'trigger' nor 'type' was specified" )
          if ( !defined( $webArgs->{entry} )
            && !defined( $webArgs->{trigger} )
            && !defined( $webArgs->{type} ) );

        # validate entry
        return ( "text/plain; charset=utf-8",
            "NOK Expected value for 'entry' cannot be empty" )
          if ( defined( $webArgs->{entry} ) && $webArgs->{entry} eq "" );

        return ( "text/plain; charset=utf-8",
            "NOK Value for 'entry' can only be: 1 0" )
          if ( defined( $webArgs->{entry} )
            && $webArgs->{entry} ne 0
            && $webArgs->{entry} ne 1 );

        # validate trigger
        return ( "text/plain; charset=utf-8",
            "NOK Expected value for 'trigger' cannot be empty" )
          if ( defined( $webArgs->{trigger} ) && $webArgs->{trigger} eq "" );

        return ( "text/plain; charset=utf-8",
            "NOK Value for 'trigger' can only be: enter|test exit" )
          if ( defined( $webArgs->{trigger} )
            && $webArgs->{trigger} ne "enter"
            && $webArgs->{trigger} ne "test"
            && $webArgs->{trigger} ne "exit" );

        # validate type
        return ( "text/plain; charset=utf-8",
            "NOK Expected value for 'type' cannot be empty" )
          if ( defined( $webArgs->{type} ) && $webArgs->{type} eq "" );

        return ( "text/plain; charset=utf-8",
            "NOK Value for 'type' can only be: Entered Leaving" )
          if ( defined( $webArgs->{type} )
            && lc( $webArgs->{type} ) ne "entered"
            && lc( $webArgs->{type} ) ne "leaving" );

        # validate date
        return (
            "text/plain; charset=utf-8",
            "NOK Specified date '"
              . $webArgs->{date} . "'"
              . " does not match ISO8601 UTC format (1970-01-01T00:00:00Z)"
          )
          if ( defined( $webArgs->{date} )
            && $webArgs->{date} !~
m/(19|20)\d\d-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([0-1][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9]\.?[0-9]*)Z/
          );

        # validate timestamp
        return (
            "text/plain; charset=utf-8",
            "NOK Specified timestamp '"
              . $webArgs->{timestamp} . "'"
              . " does not seem to be a valid Unix timestamp"
          )
          if (
            defined( $webArgs->{timestamp} )
            && (   $webArgs->{timestamp} !~ m/^\d+(\.\d+)?$/
                || $webArgs->{timestamp} > time() + 300 )
          );

        # validate locName
        return ( "text/plain; charset=utf-8",
            "NOK No whitespace allowed in id '" . $webArgs->{locName} . "'" )
          if ( defined( $webArgs->{locName} )
            && $webArgs->{locName} =~ m/(?:\s)/ );

        # validate LAT
        return (
            "text/plain; charset=utf-8",
            "NOK Specified latitude '"
              . $webArgs->{latitude}
              . "' has unexpected format"
          )
          if (
            defined $webArgs->{latitude}
            && (   $webArgs->{latitude} !~ m/^-?\d+(\.\d+)?$/
                || $webArgs->{latitude} < -90
                || $webArgs->{latitude} > 90 )
          );

        # validate LONG
        return (
            "text/plain; charset=utf-8",
            "NOK Specified longitude '"
              . $webArgs->{longitude}
              . "' has unexpected format"
          )
          if (
            defined $webArgs->{longitude}
            && (   $webArgs->{longitude} !~ m/^-?\d+(\.\d+)?$/
                || $webArgs->{longitude} < -180
                || $webArgs->{longitude} > 180 )
          );

        # validate device
        return ( "text/plain; charset=utf-8",
            "NOK Expected value for 'device' cannot be empty" )
          if ( !defined( $webArgs->{device} ) || $webArgs->{device} eq "" );

        return (
            "text/plain; charset=utf-8",
            "NOK No whitespace allowed in device '" . $webArgs->{device} . "'"
          )
          if ( defined( $webArgs->{device} )
            && $webArgs->{device} =~ m/(?:\s)/ );

        # Locative.app
        if ( defined $webArgs->{trigger} ) {
            $id     = $webArgs->{id};
            $entry  = $webArgs->{trigger};
            $lat    = $webArgs->{latitude};
            $long   = $webArgs->{longitude};
            $device = $webArgs->{device};

            if ( defined( $webArgs->{timestamp} ) ) {
                my ( $sec, $min, $hour, $d, $m, $y ) =
                  localtime( $webArgs->{timestamp} );
                $date = timelocal( $sec, $min, $hour, $d, $m, $y );
            }
        }

        # Geofency.app
        elsif ( defined $webArgs->{entry} ) {
            $id      = $webArgs->{id};
            $locName = $webArgs->{name};
            $entry   = $webArgs->{entry};
            $date    = GEOFANCY_ISO8601UTCtoLocal( $webArgs->{date} );
            $lat     = $webArgs->{latitude};
            $long    = $webArgs->{longitude};
            $address = $webArgs->{address}
              if ( defined( $webArgs->{address} ) );
            $device = $webArgs->{device};
        }

        # SMART Geofences.app
        elsif ( defined $webArgs->{type} ) {
            $id      = $webArgs->{name};
            $locName = $webArgs->{name};
            $entry   = $webArgs->{type};
            $date    = GEOFANCY_ISO8601UTCtoLocal( $webArgs->{date} );
            $lat     = $webArgs->{latitude};
            $long    = $webArgs->{longitude};
            $address = $webArgs->{address}
              if ( defined( $webArgs->{address} ) );
            $device = $webArgs->{device};
        }
        else {
            return "fatal error";
        }
    }

    # no data received
    else {
        Log3 undef, 5, "GEOFANCY: No data received";

        return ( "text/plain; charset=utf-8", "NOK No data received" );
    }

    # return error if unknown trigger
    return ( "text/plain; charset=utf-8", "$entry NOK" )
      if ( lc($entry) ne "enter"
        && lc($entry) ne "1"
        && lc($entry) ne "exit"
        && lc($entry) ne "0"
        && lc($entry) ne "test"
        && lc($entry) ne "entered"
        && lc($entry) ne "leaving" );

    $hash = $defs{$name};

    # update ROOMMATE devices associated with this device UUID
    my $matchingResident = 0;
    delete $hash->{ROOMMATES};
    if ( defined( $modules{ROOMMATE}{defptr} ) ) {
        Log3 $name, 5, "GEOFANCY $name: found defptr for ROOMMATE\n"
          . Dumper( $modules{ROOMMATE}{defptr} );

        while ( my ( $key, $value ) = each %{ $modules{ROOMMATE}{defptr} } ) {
            Log3 $name, 5, "GEOFANCY $name: Checking rr_geofenceUUIDs for $key";

            my $geofenceUUIDs = AttrVal( $key, "rr_geofenceUUIDs", undef );
            next if !$geofenceUUIDs;

            Log3 $name, 5,
"GEOFANCY $name: ROOMMATE device $key has assigned UUIDs: $geofenceUUIDs";

            $hash->{ROOMMATES} .= ",$key" if $hash->{ROOMMATES};
            $hash->{ROOMMATES} = $key if !$hash->{ROOMMATES};

            my @UUIDs = split( ',', $geofenceUUIDs );

            if (@UUIDs) {
                foreach (@UUIDs) {
                    if ( $_ eq $device ) {
                        Log3 $name, 4,
"GEOFANCY $name: Found matching UUID at ROOMMATE device $key";
                        $deviceAlias      = $key;
                        $matchingResident = 1;
                        last;
                    }
                }
            }
        }
    }

    delete $hash->{GUESTS};

    # update GUEST devices associated with this device UUID
    if ( $matchingResident == 0 && defined( $modules{GUEST}{defptr} ) ) {
        while ( my ( $key, $value ) = each %{ $modules{GUEST}{defptr} } ) {
            my $geofenceUUIDs = AttrVal( $key, "rg_geofenceUUIDs", undef );
            next if !$geofenceUUIDs;

            Log3 $name, 5,
"GEOFANCY $name: GUEST device $key has assigned UUIDs: $geofenceUUIDs";

            $hash->{GUESTS} .= ",$key" if $hash->{GUESTS};
            $hash->{GUESTS} = $key if !$hash->{GUESTS};

            my @UUIDs = split( ',', $geofenceUUIDs );

            if (@UUIDs) {
                foreach (@UUIDs) {
                    if ( $_ eq $device ) {
                        Log3 $name, 4,
"GEOFANCY $name: Found matching UUID at GUEST device $key";
                        $deviceAlias      = $key;
                        $matchingResident = 1;
                        last;
                    }
                }
            }
        }
    }

    # Device alias handling
    #
    delete $hash->{helper}{device_aliases}
      if $hash->{helper}{device_aliases};
    delete $hash->{helper}{device_names}
      if $hash->{helper}{device_names};

    if ( defined( $attr{$name}{devAlias} ) ) {
        my @devices = split( ' ', $attr{$name}{devAlias} );

        if (@devices) {
            foreach (@devices) {
                my @device = split( ':', $_ );
                $hash->{helper}{device_aliases}{ $device[0] } =
                  $device[1];
                $hash->{helper}{device_names}{ $device[1] } =
                  $device[0];
            }
        }
    }

    $deviceAlias = $hash->{helper}{device_aliases}{$device}
      if ( $hash->{helper}{device_aliases}{$device} && $matchingResident == 0 );

    Log3 $name, 4,
"GEOFANCY $name: id=$id name=$locName trig=$entry date=$date lat=$lat long=$long address:$address dev=$device devAlias=$deviceAlias";

    Log3 $name, 3,
"GEOFANCY $name: Unknown device UUID $device: Set attribute devAlias for $name or assign $device to any ROOMMATE or GUEST device using attribute r*_geofenceUUIDs"
      if ( $deviceAlias eq "-" );

    readingsBeginUpdate($hash);

    # use date for readings
    if ( $date ne "" ) {
        $hash->{".updateTime"}      = $date;
        $hash->{".updateTimestamp"} = FmtDateTime( $hash->{".updateTime"} );
        $time                       = $hash->{".updateTimestamp"};
    }

    # use local FHEM time
    else {
        $time = TimeNow();
    }

    # General readings
    readingsBulkUpdate( $hash, "state",
"id:$id trig:$entry date:$date lat:$lat long:$long dev:$device devAlias=$deviceAlias"
    );
    readingsBulkUpdate( $hash, "lastDeviceUUID", $device );
    readingsBulkUpdate( $hash, "lastDevice",     $deviceAlias );

    # update local device readings if
    # - UUID was not assigned to any resident device
    # - UUID has a defined devAlias
    if ( $matchingResident == 0 && $deviceAlias ne "-" ) {

        $id = $locName if ( defined($locName) && $locName ne "" );

        readingsBulkUpdate( $hash, "lastArr", $deviceAlias . " " . $id )
          if ( lc($entry) eq "enter"
            || lc($entry) eq "1"
            || lc($entry) eq "entered" );
        readingsBulkUpdate( $hash, "lastDep", $deviceAlias . " " . $id )
          if ( lc($entry) eq "exit"
            || lc($entry) eq "0"
            || lc($entry) eq "leaving" );

        if (   lc($entry) eq "enter"
            || lc($entry) eq "1"
            || lc($entry) eq "entered"
            || lc($entry) eq "test" )
        {
            Log3 $name, 4, "GEOFANCY $name: $deviceAlias arrived at $id";
            readingsBulkUpdate( $hash, $deviceAlias, "arrived " . $id );
            readingsBulkUpdate( $hash, "currLoc_" . $deviceAlias,     $id );
            readingsBulkUpdate( $hash, "currLocLat_" . $deviceAlias,  $lat );
            readingsBulkUpdate( $hash, "currLocLong_" . $deviceAlias, $long );
            readingsBulkUpdate( $hash, "currLocAddr_" . $deviceAlias,
                $address );
            readingsBulkUpdate( $hash, "currLocTime_" . $deviceAlias, $time );
        }
        elsif (lc($entry) eq "exit"
            || lc($entry) eq "0"
            || lc($entry) eq "leaving" )
        {
            my $currReading;
            my $lastReading;

            Log3 $name, 4,
              "GEOFANCY $name: $deviceAlias left $id and is in transit";

            # backup last known location if not "underway"
            $currReading = "currLoc_" . $deviceAlias;
            if ( defined( $hash->{READINGS}{$currReading}{VAL} )
                && $hash->{READINGS}{$currReading}{VAL} ne "underway" )
            {
                foreach ( 'Loc', 'LocLat', 'LocLong', 'LocAddr' ) {
                    $currReading = "curr" . $_ . "_" . $deviceAlias;
                    $lastReading = "last" . $_ . "_" . $deviceAlias;
                    readingsBulkUpdate( $hash, $lastReading,
                        $hash->{READINGS}{$currReading}{VAL} )
                      if ( defined( $hash->{READINGS}{$currReading}{VAL} ) );
                }
                $currReading = "currLocTime_" . $deviceAlias;
                readingsBulkUpdate(
                    $hash,
                    "lastLocArr_" . $deviceAlias,
                    $hash->{READINGS}{$currReading}{VAL}
                ) if ( defined( $hash->{READINGS}{$currReading}{VAL} ) );
                readingsBulkUpdate( $hash, "lastLocDep_" . $deviceAlias,
                    $time );
            }

            readingsBulkUpdate( $hash, $deviceAlias, "left " . $id );
            readingsBulkUpdate( $hash, "currLoc_" . $deviceAlias, "underway" );
            readingsBulkUpdate( $hash, "currLocLat_" . $deviceAlias,  "-" );
            readingsBulkUpdate( $hash, "currLocLong_" . $deviceAlias, "-" );
            readingsBulkUpdate( $hash, "currLocAddr_" . $deviceAlias, "-" );
            readingsBulkUpdate( $hash, "currLocTime_" . $deviceAlias, $time );
        }
    }

    readingsEndUpdate( $hash, 1 );

    # trigger update of resident device readings
    if ( $matchingResident == 1 ) {
        my $trigger = 0;
        $trigger = 1
          if ( lc($entry) eq "enter"
            || lc($entry) eq "1"
            || lc($entry) eq "entered"
            || lc($entry) eq "test" );
        $locName = $id if ( $locName eq "" );

        ROOMMATE_SetLocation(
            $deviceAlias, $locName, $trigger, $id, $time,
            $lat,         $long,    $address, $device
        ) if ( $defs{$deviceAlias}{TYPE} eq "ROOMMATE" );

        GUEST_SetLocation(
            $deviceAlias, $locName, $trigger, $id, $time,
            $lat,         $long,    $address, $device
        ) if ( $defs{$deviceAlias}{TYPE} eq "GUEST" );
    }

    $msg = lc($entry) . " OK";
    $msg .= "\ndevice=$device id=$id lat=$lat long=$long trig=lc($entry)"
      if ( lc($entry) eq "test" );

    return ( "text/plain; charset=utf-8", $msg );
}

sub GEOFANCY_ISO8601UTCtoLocal ($) {
    my ($datetime) = @_;
    $datetime =~ s/T/ /g if ( defined( $datetime && $datetime ne "" ) );
    $datetime =~ s/Z//g  if ( defined( $datetime && $datetime ne "" ) );

    my (
        $date, $time, $y,     $m,       $d,       $hour,
        $min,  $sec,  $hours, $minutes, $seconds, $timestamp
    );

    ( $date, $time ) = split( ' ', $datetime );
    ( $y,    $m,   $d )   = split( '-', $date );
    ( $hour, $min, $sec ) = split( ':', $time );
    $m -= 01;
    $timestamp = timegm( $sec, $min, $hour, $d, $m, $y );
    ( $sec, $min, $hour, $d, $m, $y ) = localtime($timestamp);
    $timestamp = timelocal( $sec, $min, $hour, $d, $m, $y );

    return $timestamp;
}

1;

=pod
=item helper
=begin html

    <p>
      <a name="GEOFANCY" id="GEOFANCY"></a>
    </p>
    <h3>
      GEOFANCY
    </h3>
    <ul>
      <li>Provides webhook receiver for geofencing, e.g. via the following apps:<br>
        <br>
      </li>
      <li>
        <a href="https://itunes.apple.com/app/id615538630">Geofency (iOS)</a>
      </li>
      <li>
        <a href="https://itunes.apple.com/app/id725198453">Locative (iOS)</a>
      </li>
      <li>
        <a href="http://www.egigeozone.de">EgiGeoZone (Android)</a>
      </li>
      <li>
        <a href="https://www.microsoft.com/en-us/store/apps/smart-geofences/9nblggh4rk3k">SMART Geofences (Windows 10, Windows 10 Mobile)</a>
      </li>
      <li>
        <p>
          Note: GEOFANCY is an extension to <a href="FHEMWEB">FHEMWEB</a>. You need to install FHEMWEB to use GEOFANCY.
        </p><a name="GEOFANCYdefine" id="GEOFANCYdefine"></a> <b>Define</b>
        <ul>
          <code>define &lt;name&gt; GEOFANCY &lt;infix&gt;</code><br>
          <br>
          Defines the webhook server. <code>&lt;infix&gt;</code> is the portion behind the FHEMWEB base URL (usually <code>http://hostname:8083/fhem</code>)<br>
          <br>
          Example:
          <ul>
            <code>define geofancy GEOFANCY geo</code><br>
          </ul><br>
          The webhook will be reachable at http://hostname:8083/fhem/geo in that case.<br>
          <br>
        </ul><a name="GEOFANCYset" id="GEOFANCYset"></a> <b>Set</b>
        <ul>
          <li>
            <b>clear</b> &nbsp;&nbsp;readings&nbsp;&nbsp; can be used to cleanup auto-created readings from deprecated devices.
          </li>
        </ul><br>
        <br>
        <a name="GEOFANCYattr" id="GEOFANCYattr"></a> <b>Attributes</b><br>
        <br>
        <ul>
          <li>devAlias: Mandatory attribute to assign device name alias to an UUID in the format DEVICEUUID:Aliasname (most readings will only be created if devAlias was defined).<br>
                        Separate using <i>blank</i> to rename multiple device UUIDs.<br>
                        <br>
                        Should you be using GEOFANCY together with <a href="#ROOMMATE">ROOMMATE</a> or <a href="#GUEST">GUEST</a> you might consider using attribute r*_geofenceUUIDs directly at those devices instead.
          </li>
        </ul><br>
        <br>
        <b>Usage information / Hints on Security</b><br>
        <br>
        <ul>
          Likely your FHEM installation is not reachable directly from the internet (good idea!).<br>
          It is recommended to have a reverse proxy like <a href="http://loredo.me/post/116633549315/geeking-out-with-haproxy-on-pfsense-the-ultimate">HAproxy</a>, <a href="http://www.apsis.ch/pound/">Pound</a> or <a href="https://www.varnish-cache.org/">Varnish</a> in front of FHEM where you can make sure access is only possible to a specific URI like /fhem/geo. Apache or Nginx might do as well. However, in case you have Apache or Nginx running already you should still consider one of the named reverse proxies in front of it for fine-grain security configuration.<br>
          <br>
          You might also want to think about protecting the access by using HTTP Basic Authentication and encryption via TLS/SSL. Using TLS offloading in the reverse proxy software is highly recommended and software like HAproxy provides high control of data flow for TLS.<br>
          <br>
          Also the definition of a dedicated FHEMWEB instance for that purpose together with <a href="#allowed">allowed</a> might help to restrict FHEM's functionality (e.g. set attributes allowedCommands and allowedDevices to ",". Note that attributes <i>hiddengroup</i> and <i>hiddenroom</i> of FHEMWEB do NOT protect from just guessing/knowing the correct URI but would help tremendously to prevent easy inspection of your FHEM setup.)<br>
          <br>
          To make that reverse proxy available from the internet, just forward the appropriate port via your internet router.<br>
          <br>
          The actual solution on how you can securely make your GEOFANCY webhook available to the internet is not part of this documentation and depends on your own skills.
        </ul><br>
        <br>
        <b>Integration with Home Automation</b><br>
        <br>
        <ul>
          You might want to have a look to the module family of <a href="#ROOMMATE">ROOMMATE</a>, <a href="#GUEST">GUEST</a> and <a href="#RESIDENTS">RESIDENTS</a> for an easy processing of GEOFANCY events.
        </ul>
      </li>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="GEOFANCY" id="GEOFANCY"></a>
    </p>
    <h3>
      GEOFANCY
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#GEOFANCY'>GEOFANCY</a>
    </ul>

=end html_DE

=cut
