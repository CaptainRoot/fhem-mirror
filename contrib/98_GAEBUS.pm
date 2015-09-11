##############################################
# $Id: 98_GAEBUS.pm 1 2015-07-03 00:00:00 Andreas Goebel $
# derived from 00_TUL.pm
#
# 17.07.2015 : A.Goebel : initiale Version mit loop, readingname via attribut, keine writes
# 21.07.2015 : A.Goebel : start implementation for "set .. write"
# 23.07.2015 : A.Goebel : event-on-change-reading added to attributes
# 08.09.2015 : A.Goebel : limit number of socket-open retries in GetUpdates loop
# 10.09.2015 : A.Goebel : fix html code of commandref
# 11.09.2015 : A.Goebel : add attribute "ebusWritesEnable:0,1"
# 11.09.2015 : A.Goebel : add set w~ commands to set attributes for writing 
# 11.09.2015 : A.Goebel : add set <write-reading> command to write to ebusd

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use IO::Socket;
use IO::Select;

sub GAEBUS_Attr(@);

sub GAEBUS_OpenDev($$);
sub GAEBUS_CloseDev($);
sub GAEBUS_SimpleWrite(@);
sub GAEBUS_Disconnected($);
sub GAEBUS_Shutdown($);

sub GAEBUS_doEbusCmd($$$$$);
sub GAEBUS_GetUpdates($);

my %gets = (    # Name, Data to send to the GAEBUS, Regexp for the answer
#  "raw"      => ["r", '.*'],
);

my %getsToRead = ();

my %sets = (
#  "raw"       => "",
  "reopen"    => []
);

my %setsForWriting = ();

my $allSetParams           = "";
my $allSetParamsForWriting = "";
my $allGetParams           = "";
my $delimiter              = "~";

my $attrsDefault = "do_not_notify:1,0 dummy:1,0 showtime:1,0 loglevel:0,1,2,3,4,5,6 event-on-change-reading ebusWritesEnabled:0,1";
my %ebusCmd  = ();

sub
GAEBUS_Initialize($)
{
  my ($hash) = @_;

# Normal devices
  $hash->{DefFn}      = "GAEBUS_Define";
  $hash->{UndefFn}    = "GAEBUS_Undef";
  $hash->{GetFn}      = "GAEBUS_Get";
  $hash->{SetFn}      = "GAEBUS_Set";
  #$hash->{StateFn}    = "GAEBUS_SetState";
  $hash->{AttrFn}     = "GAEBUS_Attr";
  $hash->{AttrList}   = $attrsDefault;
  $hash->{ShutdownFn} = "GAEBUS_Shutdown";

  GAEBUS_ReadCSV($hash);

  $allSetParams = "";
  foreach my $setval (sort keys %sets) 
  {
	Log3 ($hash, 4, "GAEBUS Initialize params for set: $setval");
	if ( (@{$sets{$setval}}) > 0)
	{
          $allSetParams .= $setval.":".join (",", @{$sets{$setval}})." ";
	}
	else
	{
          $allSetParams .= $setval." ";
	}
	#Log3 ($hash, 2, "GAEBUS Initialize: $setval:$allSetParams");
  }

  $allSetParamsForWriting = "";
  foreach my $setval (sort keys %setsForWriting) 
  {
	Log3 ($hash, 4, "GAEBUS Initialize params for setsForWriting: $setval");
	if ( (@{$setsForWriting{$setval}}) > 0)
	{
          $allSetParamsForWriting .= $setval.":".join (",", @{$setsForWriting{$setval}})." ";
	}
	else
	{
          $allSetParamsForWriting .= $setval." ";
	}
	#Log3 ($hash, 2, "GAEBUS Initialize: $setval:$allSetParamsForWriting");
  }

  $allGetParams = "";
  foreach my $getval (sort keys %gets) 
  {
	Log3 ($hash, 4, "GAEBUS Initialize params for get: $getval");
	if ( (@{$gets{$getval}}) > 0)
	{
          $allGetParams .= $getval.":".join (",", @{$gets{$getval}})." ";
	}
	else
	{
          $allGetParams .= $getval." ";
	}
	#Log3 ($hash, 2, "GAEBUS Initialize: $getval:$allGetParams");
  }
}

#####################################
sub
GAEBUS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 3) {
    my $msg = "wrong syntax: define <name> GAEBUS <device-addr>[:<port>] [interval]";
    Log (2, $msg);
    return $msg;
  }

  GAEBUS_CloseDev($hash);

  my $name     = $a[0];
  my $devaddr  = $a[2];
  my $interval = $a[3];

  $hash->{DeviceName}    = $hash->{NAME};
  $hash->{DeviceAddress} = $devaddr;
  $hash->{Interval}      = defined ($interval) ? int ($interval) : 150;
  $hash->{UpdateCnt}     = 0;
  
  my $ret = GAEBUS_OpenDev($hash, 0);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{Interval}, "GAEBUS_GetUpdates", $hash, 0);

  return undef;
}


#####################################
sub
GAEBUS_Undef($$)
{
  my ($hash, $arg) = @_;
  GAEBUS_CloseDev($hash); 
  return undef;
}

#####################################
sub GAEBUS_Shutdown($)
{
  my ($hash) = @_;
  GAEBUS_CloseDev($hash); 
  return undef;
}

#####################################
sub
GAEBUS_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set GAEBUS\" needs at least one parameter" if(@a < 2);

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);

  #return "No $a[1] for dummies" if(IsDummy($name));

  #Log3 ($hash, 3, "ebus1: reopen $name");

  if ($type eq "reopen") {
    Log3 ($hash, 3, "ebus1: reopen");
    GAEBUS_CloseDev($hash);
    GAEBUS_OpenDev($hash,0);
    return undef;
  }

  # handle commands defined in %sets

  if (defined ($sets{$type}))
  {
	unless (grep {$_ eq $arg} @{$sets{$type}})
	{
		return "invalid parameter";
	}

        my $attrname = $type.$delimiter.$arg;
        $attrname =~ s/\#install/install/;

	Log3 ($hash, 3, "$name: set $attrname");
        addToDevAttrList($name, $attrname);
	$attr{$name}{$attrname} = "" unless (defined $attr{$name}{$attrname});

        return undef;
  }

  #
  # extend possible parameters by the readings defined for writing in attributes
  #


  my %writings = ();

  my $actSetParams = "$allSetParams ";

  my $ebusWritesEnabled = (defined($attr{$name}{"ebusWritesEnabled"})) ? $attr{$name}{"ebusWritesEnabled"} : 0;

  if ($ebusWritesEnabled) {
    $actSetParams .= "$allSetParams$allSetParamsForWriting " if ($ebusWritesEnabled);

    foreach my $oneattr (sort keys %{$attr{$name}})
    {
      my $readingname    = $attr{$name}{$oneattr};
      my $readingcmdname = $oneattr;
      $readingname       =~ s/:.*//;
  
      # only for "w" commands
      if ($oneattr =~ /^w.*$delimiter.*$delimiter.*$delimiter.*$/)
      {
        unless ($readingname =~ /^\s*$/ or $readingname eq "1")
        {
          $writings{$readingname} = $readingcmdname;
          #Log3 ($name, 2, "$name SetParams $readingname");
        }
      }
  
      #Log3 ($name, 4, "$name Set attr name $readingname");
      #Log3 ($name, 4, "$name Set attr cmd  $readingcmdname");
    }
    $actSetParams .= join (" ", sort keys %writings);
  

    # handle write commands (which were defined above)

    if (defined ($setsForWriting{$type}))
    {
  	unless (grep {$_ eq $arg} @{$setsForWriting{$type}})
	{
		return "invalid parameter";
	}

        my $attrname = $type.$delimiter.$arg;
        $attrname =~ s/\#install/install/;

	Log3 ($hash, 3, "$name: set $attrname");
        addToDevAttrList($name, $attrname);
	$attr{$name}{$attrname} = "" unless (defined $attr{$name}{$attrname});

        return undef;
    }

    if (defined ($writings{$type}))
    {
      # HERE
      foreach my $oneattr (sort keys %{$attr{$name}})
      {
        next unless ($oneattr =~ /^w.*$delimiter.*$delimiter.*$delimiter.*$/);
     
        my $readingname    = $attr{$name}{$oneattr};
        next if ($readingname ne $type);

        my $answer = GAEBUS_doEbusCmd ($hash, "w", $readingname, $oneattr, $arg);
        return "$answer";
      }
    }

  }


  return "Unknown argument $type, choose one of " . $actSetParams
  	if(!defined($sets{$type}));


  #if($type eq "raw") {
  #  Log3 $hash, 3, "set $name $type $arg";
  #  GAEBUS_SimpleWrite($hash, $arg);
  #}
  return undef;
}

#####################################
sub
GAEBUS_Get($@)
{
  my ($hash, @a) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};

  my $arg = (defined($a[2]) ? $a[2] : "");
  my $rsp;
  my $varname = $a[0];


  my $readingname = ""; 
  my $readingcmdname  = ""; 

  return "\"get $type\" needs at least one parameter" if(@a < 2);

  # extend possible parameters by the readings defined in attributes

  my %readings = ();
  my $actGetParams .= "$allGetParams reading:";
  foreach my $oneattr (sort keys %{$attr{$name}})
  {
    my $readingname    = $attr{$name}{$oneattr};
    my $readingcmdname = $oneattr;
    $readingname       =~ s/:.*//;

    # only for "r" commands
    if ($oneattr =~ /^r.*$delimiter.*$delimiter.*$delimiter.*$/)
    {
      unless ($readingname =~ /^\s*$/ or $readingname eq "1")
      {
        $readings{$readingname} = $readingcmdname;
        #Log3 ($name, 2, "$name GetParams $readingname");
      }
    }

    #Log3 ($name, 4, "$name Get attr name $readingname");
    #Log3 ($name, 4, "$name Get attr cmd  $readingcmdname");
  }
  $actGetParams .= join (",", sort keys %readings);


  # handle "read" parameters and update Reading

  if ($a[1] eq "reading")
  {
    my $readingname = $a[2];
    my $readingcmdname = $readings{$readingname};

    Log3 ($name, 4, "$name Get name $readingname");
    Log3 ($name, 4, "$name Get cmd r $readingcmdname");

    my $answer = GAEBUS_doEbusCmd ($hash, "r", $readingname, $readingcmdname, "");

    #return (defined($answer ? $answer : ""));
    return "$answer";

  }

  # other read commands

  if ($a[1] =~ /^r$delimiter/) 
  {
    my $readingname = "";
    my $readingcmdname = $a[1].$delimiter.$a[2];

    Log3 ($name, 3, "$name get cmd v $readingcmdname");

    my $answer = GAEBUS_doEbusCmd ($hash, "v", $readingname, $readingcmdname, "");
    #return (defined($answer ? $answer : ""));
    return "$answer";

  }

  # handle commands from %gets and show result from ebusd


  return "Unknown argument $a[1], choose one of " . $actGetParams
  	if(!defined($gets{$a[1]}));


  #return "No $a[1] for dummies" if(IsDummy($varname));

  return "nix"; 

  #GAEBUS_SimpleWrite($hash, "B".$gets{$a[1]}[0] . $arg);

# HERE READ
#  $rsp = GAEBUS_SimpleRead($hash);

  if(!defined($rsp)) {
    GAEBUS_Disconnected($hash);
    $rsp = "No answer";
  } 

  $hash->{READINGS}{$a[1]}{VAL} = $rsp;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $rsp";
}

#####################################
sub
GAEBUS_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

########################
sub
GAEBUS_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  
  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  }

  #delete($selectlist{"$name.$dev"});
  #delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
  $hash->{STATE} = "closed";
}

########################
sub
GAEBUS_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  my $host = $hash->{DeviceAddress};
  my $port = 8888;
  if($host =~ m/^(.+):(.+)$/) { # host[:port]
	$host = $1;
	$port = $2;
  }

  $hash->{PARTIAL} = "";
  Log3 $hash, 3, "GAEBUS opening $name device $host($port)"
        if($reopen == 0);

  # This part is called every time the timeout (5sec) is expired _OR_
  # somebody is communicating over another TCP connection. As the connect
  # for non-existent devices has a delay of 3 sec, we are sitting all the
  # time in this connect. NEXT_OPEN tries to avoid this problem.

  if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
    Log3 $hash, 5, "GAEBUS NEXT_OPEN prevented opening $name device $host($port)";
    return;
  }

  my $conn = new IO::Socket::INET (
	PeerAddr => "$host",
	PeerPort => '8888',
	Proto    => 'tcp',
	Reuse    => 0,
	Timeout  => 10
	);

  if(defined ($conn)) {
    delete($hash->{NEXT_OPEN});


  } else {
    Log(3, "Can't connect to $dev: $!") if(!$reopen);

    #$readyfnlist{"$name.$dev"} = $hash;

    $hash->{STATE} = "disconnected";
    $hash->{NEXT_OPEN} = time()+60;
    return "";
  }

  my $sel = new IO::Select($conn);

  $hash->{DevType} = 'EBUSD';
  $hash->{TCPDev} = $conn;
  $hash->{FD} = $conn->fileno();
  $hash->{SELECTOR} = $sel;

  #delete($readyfnlist{"$name.$dev"});
  #$selectlist{"$name.$dev"} = $hash;

  if($reopen) {
    Log3 $hash, 1, "GAEBUS $dev reappeared ($name)";
  } else {
    Log3 $hash, 3, "GAEBUS device opened ($name)";
  }

  #$hash->{STATE}="Initialized";
  $hash->{STATE}="Connected";

  DoTrigger($name, "CONNECTED") if($reopen);
  return 0;
}

sub
GAEBUS_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted or RFR

  Log3 $hash, 1, "$dev disconnected, waiting to reappear";
  GAEBUS_CloseDev($hash);
  #$readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

sub
GAEBUS_Attr(@)
{
  my @a = @_;
  my ($action, $name, $attrname, $attrval) = @a;

  $attrval = "" unless defined ($attrval);

  if ($action eq "del")
  {
    my $userattr = $attr{$name}{userattr};
    #Log3 ($hash, 2, ">$userattr<>$attrname<");
    if ( " $userattr " =~ / $attrname / ) 
    {
      #Log3 ($hash, 2, "match");
      # " a" or "^a$"
      $userattr =~ s/ *$attrname//;
      if ($userattr eq "")
      {
        delete($attr{$name}{userattr});
      }
      else
      {
        $attr{$name}{userattr} = $userattr;
      }

    }

    # delete reading if attribute name contains $delimiter

    if ($attrname =~ /^.*$delimiter/) {
      my $reading = $attr{$name}{$attrname};
      $reading    =~ s/:.*//;

      Log3 ($name, 3, "$name: delete reading: $reading");
      delete($defs{$name}{READINGS}{$reading});
    }

    return undef;
  }
  elsif ($action eq "set")
  {

    if (defined $attr{$name}{$attrname}) 
    {
      my $oldreading = $attr{$name}{$attrname};
      $oldreading    =~ s/:.*//;
      my $newreading = $attrval;
      $newreading    =~ s/:.*//;
 
      if ($oldreading ne $newreading)
      {
        #Log3 ($name, 2, "$name: adjust reading: $oldreading");

        if (defined($defs{$name}{READINGS}{$oldreading}))
        {
          unless ($newreading =~ /^1*$/)  # matches "1" or ""
          {
            #Log3 ($name, 2, "$name: change attribute $attrname ($oldreading -> $newreading)");

            $defs{$name}{READINGS}{$newreading}{VAL}  = $defs{$name}{READINGS}{$oldreading}{VAL};
            $defs{$name}{READINGS}{$newreading}{TIME} = $defs{$name}{READINGS}{$oldreading}{TIME};
          }

          delete($defs{$name}{READINGS}{$oldreading});
          
        }
      }
    }
  }

  Log3 (undef, 2, "called GAEBUS_Attr($a[0],$a[1],$a[2],<$a[3]>)");
 
  return undef;
}

sub
GAEBUS_ProcessCSV($$)
{
  my ($hash, $file) = @_;

  if (!open (CSV, "<$file"))
  {
      Log3 ($hash, 2, "GAEBUS: cannot open $file");
      return undef;
  }
  else
  {

    my $line;
    my $buffer = "";

    my $actCircuit = "";
    my %circuits   = ();
    my $defCircuit = "$file";

    $defCircuit =~  s,^.*/,,;
    $defCircuit =~  s/\.csv$//;

    while (<CSV>)
    {
      next if /^#/;
      next if /^\s$/;
      s/\r//;
    
      chomp;

      $line = $_;
      $line =~ s/ /_/g; # no blanks in names and comments
      $line =~ s/$delimiter/_/g; # clean up the delimiter within the text
      #$line =~ s/\|/_/g; # later used as delimiter in arguments

      my ($io, $circuit, $vname, $comment, @params) = split (",", $line, 5);

      # handle defaults: "^*"

      if ($io =~ /^\*(.*)/) 
      {
        my $rwkey = $1;

        if ($circuit ne "")
        {
          #print "new circuit found $rwkey: $circuit\n";
          $circuits{$rwkey} = $circuit;
          next;
        }
      }

      # collect variables

      foreach my $dir (split (";", $io.";"))
      {
        if ($circuit ne "")
        {
          $actCircuit = $circuit;
        }
        elsif (defined ($circuits{$dir}))
        {
          $actCircuit = $circuits{$dir};
        }
        else
        {
          $actCircuit = $defCircuit;
        }
        #printf "%-3s %-12s %-40s %-s\n", $dir, $actCircuit, $vname, $comment;
        #Log3 $hash, 3, printf "%-3s %-12s %-40s %-s\n", $dir, $actCircuit, $vname, $comment;
        #Log3 $hash, 3, "$dir, $actCircuit, $vname, $comment";

	my $dirSimple = substr($dir, 0,1);
	if ($dirSimple =~ /^[rw]/)
        {
          my $rkey = join (";", ($dirSimple, $actCircuit, $vname));
          $ebusCmd{$rkey} = $comment;
        }

      }

      #print "$io $actCircuit\n";
    }
    close (CSV);
  }
}

sub 
GAEBUS_ReadCSV($)
{
  my $hash = shift;
  my $dir = "./ebusd";

  %ebusCmd  = ();

  if (opendir INDIR, $dir)
  {
    my @infiles = grep /^[^\.].*\.csv$/, readdir INDIR; # all files exept those starting with "."
    foreach my $file (@infiles)
    {
      Log3 ($hash, 4, "GAEBUS: process config $file");
      GAEBUS_ProcessCSV($hash, $dir."/".$file);
    }
    closedir INDIR;

    %sets = ( "reopen" => [] );
    %gets = ( );
    %setsForWriting = ( );

    my $comment;
    foreach my $key (sort keys %ebusCmd)
    {
      $comment = $ebusCmd{$key};

      my ($io,$class,$var) = split (";", $key, 3);

      push @{$sets{$io.$delimiter.$class}}, $var.$delimiter.$comment if ($io eq "r");

      push @{$setsForWriting{$io.$delimiter.$class}}, $var.$delimiter.$comment if ($io eq "w");

      push @{$gets{$io.$delimiter.$class}}, $var.$delimiter.$comment if ($io eq "r" or $io eq "u");
      
      Log3 ($hash, 5, "GAEBUS: add attr $key $comment");
    }

  } 
  else  
  {
    Log3 ($hash, 2, "cannot open dir $dir");
  }
}

sub 
GAEBUS_doEbusCmd($$$$$)
{
  my $hash           = shift;
  my $action         = shift; # "r" = set reading, "v" = verbose mode, "w" = write to ebus
  my $readingname    = shift;
  my $readingcmdname = shift;
  my $writeValues    = shift;
  my $actMessage;
  my $name = $hash->{NAME};

  if (($hash->{STATE} ne "Connected") or (!$hash->{TCPDev}->connected()) )
  {
    Log3 ($name, 2, "$name device closed. Try to reopen");
    GAEBUS_CloseDev($hash);
    GAEBUS_OpenDev($hash,1);

    return undef unless ($hash->{STATE} eq "Connected");
  }

  my $timeout = 1.8;
  $timeout = 10 if ($action eq "v");
  $timeout = 10 if ($action eq "w");


  my ($io,$class,$var,$comment) = split ($delimiter, $readingcmdname, 4);

  my $cmd = "";

  if ($action eq "w") {
    $cmd = "$io ";
    $cmd .= "-c $class $var ";
    $cmd .= "$writeValues";

  } else {

    $cmd = "$io -f ";
    $cmd .= "-v " if ($action eq "v");
    $cmd .= "-c $class $var";
  }

  Log3 ($name, 3, "$name execute $cmd");

  if ($hash->{SELECTOR}->can_read(0))
  {
    sysread ($hash->{TCPDev}, $actMessage, 4096);
    $actMessage =~ s/\n//g;
    Log3 ($name, 2, "$name old answer $actMessage\n");
  }

  syswrite ($hash->{TCPDev}, $cmd."\n");
  if ($hash->{SELECTOR}->can_read($timeout))
  {
    #Log3 ($name, 2, "$name try to read");
    sysread ($hash->{TCPDev}, $actMessage, 4096);
    $actMessage =~ s/\n//g;
    $actMessage =~ s/;/ /g;

    Log3 ($name, 3, "$name answer $action $readingname $actMessage");

    unless ($actMessage =~ "Usage:") # pass Usage: directly
    {
      # no Usage: message
      unless ($actMessage =~ /^ERR:/) # pass ERR: message directly
      {
        # no ERR: message
        # = normal answer

        if ($action eq "r") {
          if (defined ($readingname)) {
            readingsSingleUpdate ($hash,  $readingname, "$actMessage", 1);
          }
        }

      }
    } 

    return undef if ($action eq "r");
    return $actMessage;
  }
  else
  {
    return "timeout reading answer for ($readingname) $cmd";
  }

}

sub 
GAEBUS_GetUpdates($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $readingname = "";
  my $tryOpenCnt  = 2; # no of tries to open the device, before giving up

  $hash->{UpdateCnt} = $hash->{UpdateCnt} + 1;

  foreach my $oneattr (keys %{$attr{$name}})
  {
    # only for "r" commands
    if ($oneattr =~ /^r.*$delimiter.*$delimiter.*$delimiter.*$/)
    {

      my ($readingname, $doCntNo) = split (":", $attr{$name}{$oneattr}, 2); # split name from cycle number
      $doCntNo = 1 unless (defined ($doCntNo));

      Log3 ($name, 5, "$name GetUpdates: $readingname:$doCntNo");

      next if ($readingname =~ /^\s*$/);
      next if ($readingname eq "1");

      #Log3 ($name, 2, "$name check modulo ".$hash->{UpdateCnt}." mod $doCntNo -> ".($hash->{UpdateCnt} % $doCntNo));
      if (($hash->{UpdateCnt} % $doCntNo) == 0)
      {
        my $answer = GAEBUS_doEbusCmd ($hash, "r", $readingname, $oneattr, "");
      }

      # limit number of reopens if ebusd cannot be reached
      if (($hash->{STATE} ne "Connected") or (!$hash->{TCPDev}->connected()) )
      {
        if (--$tryOpenCnt <= 0) 
        {
          Log3 ($name, 2, "$name: not connected, stop GetUpdates loop");
          last;
        }
      }

    }
  }

  InternalTimer(gettimeofday()+$hash->{Interval}, "GAEBUS_GetUpdates", $hash, 1);

}

1;

=pod
=begin html

<a name="GAEBUS"></a>
<h3>GAEBUS</h3>
<ul>

  <table>
  <tr><td>
  The GAEBUS module is the representation of a Ebus connector in FHEM.
  The GAEBUS module is designed to connect to ebusd (ebus daemon) via a socket connection (default is port 8888) <br>

  </td><td>
  <img src="IMG_0483.jpg" width="100%" height="100%"/>
  </td></tr>
  </table>

  <a name="GAEBUS"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; GAEBUS &lt;device-addr&gt;[:&lt;port&gt;] [&lt;interval&gt;];</code> <br>
    <br>
    &lt;device-addr&gt;[:&lt;port&gt;] specifies the host:port of the ebusd device. E.g.
    192.168.0.244:8888 or servername:8888. When using the standard port, the port can be omitted.
    <br><br>

    Example:<br>
    <code>define ebus1 GAEBUS localhost 300</code>
    <br><br>
    When initializing the object the configuration of the ebusd (.csv files from /etc/ebusd) are read.<br>
    The files need to be copied into a directory "ebusd" (normally /opt/fhem/ebusd) on the server running fhem.<br>
       

  </ul>
  <br>

  <a name="GAEBUS"></a>
  <b>Set </b>
  <ul>
    <li>reopen<br>
        Will close and open the socket connection.
        </li><br>
    <li>[r]~&lt;class&gt; &lt;variable-name&gt;~&lt;comment from csv&gt;<br>
        Will define a attribute with the following syntax:<br>
        [r]~&lt;class&gt;~&lt;variable-name&gt;~&lt;comment from csv&gt<br>
        Valid combinations are read from the .csv files in directory "ebusd" and are selectable<br>
        Values from the attributes will be used as the name for the reading which are read from ebusd in the interval specified.<br>
        </li><br>
    <li>[w]~&lt;class&gt; &lt;variable-name&gt;~&lt;comment from csv&gt;<br>
        Will define a attribute with the following syntax:<br>
        [w]~&lt;class&gt;~&lt;variable-name&gt;~&lt;comment from csv&gt<br>
        They will only appear if the attribute "ebusWritesEnabled" is set to "1"<br>
        Valid combinations are read from the .csv files in directory "ebusd" and are selectable<br>
        Values from the attributes will be used for set commands to modify parameters for ebus devices<br>
        Hint: if the values for the attributes are prefixed by "set-" then all possible parameters will be listed in one block<br>
        </li><br>
  </ul>

  <a name="GAEBUS"></a>
  <b>Get</b>
  <ul>
    <li>reading &lt;reading-name&gt<br>
        Will read the actual value form ebusd and update the reading.
        </li><br>

    <li>[r]~&lt;class&gt; &lt;variable-name&gt;~&lt;comment from csv&gt;<br>
        Will read this variable from the ebusd and show the result as a popup.<br>
        Valid combinations are read from the .csv files in directory "ebusd" and are selectable<br>
        </li><br>

  </ul>
  <br>

  <a name="GAEBUS"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li>ebusWritesEnabled 0,1<br>
        disable (0) or enable (1) that commands can be send to ebus devices<br>
        See also description for Set and Get<br>
        </li><br>
    <li>Attributes of the format<br>
        <code>[r]~&lt;class&gt;~&lt;variable-name&gt;~&lt;comment from csv&gt;</code><br>
        define variables that can be retrieved from the ebusd.
        They will appear when they are defined by a "set" command as described above.<br>
        The value assigned to an attribute specifies the name of the reading for this variable.<br>
        The name of the reading can be suffixed by "&lt;number&gt;" which is a multiplicator for 
        the evaluation within the specified interval. (eg. OutsideTemp:3 will evaluate this reading every 3-th cycle)<br>
        </li><br>
    <li>Attributes of the format<br>
        <code>[w]~&lt;class&gt;~&lt;variable-name&gt;~&lt;comment from csv&gt;</code><br>
        define parameters that can be changed on ebus devices (using the write command from ebusctl)
        They will appear when they are defined by a "set" command as described above.<br>
        The value assigned to an attribute specifies the name that will be used in set to change a parameter for a ebus device.<br>
        </li><br>
  </ul>
  <br>
</ul>

=end html
=cut
