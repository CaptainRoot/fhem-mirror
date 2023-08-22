# $Id$
# svn commit -m "Cron.pm: wip" lib/FHEM/Scheduler/Cron.pm
package FHEM::Scheduler::Cron;

use v5.14;

use strict;
use warnings;
use utf8;
use POSIX qw( strftime );
use List::Util qw ( any first );
use Time::HiRes qw( time );
use Time::Local qw( timelocal );

our $REVISION;


BEGIN {
	no strict 'refs';
	${ *{__PACKAGE__.'::REVISION'}} = ('$Id$' =~ m/^\$Id:\s*(.*)\s*\$$/)[0] || __PACKAGE__. ' (no SVN ID)';
}

# class
sub new {
	my $class = shift;
	my $cron_text = shift;
	my $param = shift;

	my $self = bless {
	}, $class;

	*log = \&_log;
	$self->log(5, '%s loaded', $REVISION) if $ENV{EXTENDED_DEBUG};

	# sort of cache, in general the next expected "from_"
	# required to synchronize the pointer logic for more efficiency and speed
	$self->{working_date} = '';
	$self->{working_time} = '';

	VALIDATE: {
		do {$self->{error} = sprintf("no cron expression"); last VALIDATE} if (not $cron_text);
		do {$self->{error} = sprintf("cron expression exceeds limit"); last VALIDATE} if (length($cron_text) > 255);
		last VALIDATE if (not $self->_parse_cron_text($cron_text));
		# validate that the date can ever become true 
		if (scalar @{$self->{list_of_mdays}} ) {
			my $first = $self->{list_of_mdays}->[0];	
			my $ok = 0;
			$ok ||= 1 if ($first <= 29);
			$ok ||= any { sub{ my $a = shift; any { $a == $_ } (1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12) }->($_) } @{$self->{list_of_months}} if ($first == 30);
			$ok ||= any { sub{ my $a = shift; any { $a == $_ } (1, 3, 5, 7, 8, 10, 12) }->($_) } @{$self->{list_of_months}} if ($first == 31);
			if (not $ok) {
				$self->{error} = "day and month will never become true";
				$self->log(2, '%s', $self->{error}) if $ENV{EXTENDED_DEBUG};
				last VALIDATE;
			}
		}
	}
	# $self->log(2, '%s', $self->{error}) if ($self->{error} and $ENV{EXTENDED_DEBUG}); 
	return wantarray ? ($self, $self->{error}) : $self;
}

# public entrance
# does validation and gate keeper functions
sub next {
	my $self = shift;
	my $from = shift;

	# validate input
	my $from_date = substr($from, 0, 8);

	

	# internal method
	return $self->_next($from);

}

sub _next {
	my $self = shift;
	my $from = shift;

	# validations have already been passed in the public next()
	my $from_date = substr($from, 0, 8);
	my $from_time = substr($from, 8, 6);

	$self->log(5, '(reference/in) from_date:%s, from_time:%s', $from_date, $from_time) if $ENV{EXTENDED_DEBUG};

	my ($next_date, $next_time, $day_changed);

	# If there is a discrepancy between from_date and working_date, we must first perform the next_date calculation. 
	# Otherwise, this has already been done in previous rounds and can be skipped for efficiency and speed reasons.
	if ($from_date ne $self->{working_date}) {
		# reset pointer
		undef $self->{month_ptr};
		undef $self->{mday_ptr};
		$self->{working_date} = $next_date = $self->_next_date($from_date, 1); # inclusive, the from_date is possible
	} else {
		# load from cache
		$next_date = $self->{working_date};
	}

	# if (($from_time ne $self->{working_time}) or 
	# ($from_date ne $next_date)) {
	if ($from_time ne $self->{working_time}) {
		# reset pointer
		undef $self->{hour_ptr};
		undef $self->{minute_ptr};
	}

	# time search: 
	if ($from_date eq $self->{working_date}) {
	# if ($from_date eq $next_date) {
		# same day, therefore start with from_time (NON inclusive: >)
		($next_time, $day_changed) = $self->_next_time($from_time);
		$self->{working_time} = $next_time;
	} else {
		# new day, therefore start with from_time = 000000 (inclusive: >=)
		# that also requires a pointer reset, done above
		($next_time, $day_changed) = $next_time = $self->_next_time(000000, 1);
		$self->{working_time} = $next_time;
	}

	# day changed (overflow) in time search?
	if ($day_changed) {
		# find next date, (NON inclusive: >)
		# No need to seach time again, thats done with the overflow already
		$self->{working_date} = $next_date = $self->_next_date($from_date);
	}

	$self->log(5, '(result/out) next_date:%s, next_time:%s', $next_date, $next_time) if $ENV{EXTENDED_DEBUG};
	return $next_date.$next_time;
}

sub _log {
	my $self = shift;
	my ($verbose, $message, @args) = @_;
	no if $] >= 5.022, 'warnings', qw( redundant missing );
	no warnings "uninitialized";
	local $\ = "\n";
	# printf ('%s#%d: ', (split '::', (caller(1))[3])[-1], (caller(0))[2]);
	printf ('#%4d%20.20s: ', (caller(0))[2], (split '::', (caller(1))[3])[-1]);
	printf($message, @args);
	print;
	return;
}

# parser functions
sub _parse_cron_text {
	my $self = shift;
	my $cron_text = shift;

	my ($minute, $hour, $mday, $month, $wday, $remainder) = split /\s/, $cron_text;

	$self->log(5, 'parse cron expression: %s', $cron_text) if $ENV{EXTENDED_DEBUG};
	
	{
		my $href = {};
		my @list = split(',', $minute);
		foreach my $item (@list) {
			$self->log(5, 'about to parse minute item: %s', $item) if $ENV{EXTENDED_DEBUG};
			if (not $self->_parse_minute_item($item, $href)) {
				$self->{error} = "syntax error in minute item: $item";
				$self->log(5, 'syntax error in minute item: %s', $item) if $ENV{EXTENDED_DEBUG};
				return;
			}
		}
		# numerical sort keys and create the list
		@{$self->{list_of_minutes}} = sort { $a <=> $b } keys %$href;
		$self->log(5, 'list_of_minutes: %s', join(',', @{$self->{list_of_minutes}})) if $ENV{EXTENDED_DEBUG};
	}

	{
		my $href = {};
		my @list = split(',', $hour);
		foreach my $item (@list) {
			$self->log(5, 'about to parse hour item: %s', $item) if $ENV{EXTENDED_DEBUG};
			if (not $self->_parse_hour_item($item, $href)) {
				$self->{error} = "syntax error in hour item: $item";
				$self->log(5, 'syntax error in hour item: %s', $item) if $ENV{EXTENDED_DEBUG};
				return;
			}
		}
		# numerical sort keys and create the list
		@{$self->{list_of_hours}} = sort { $a <=> $b } keys %$href;
		$self->log(5, 'list_of_hours: %s', join(',', @{$self->{list_of_hours}})) if $ENV{EXTENDED_DEBUG};
	}

	{
		my $href = {};
		my @list = split(',', $mday);
		# weired mday/wday logic:
		# (1) if mday = * and wday = * then expand mdays (DO NOT expand wdays) (it would work but it doesnt make sense to use both)
		# (2) if mday constrained and wday constained then expand mdays and wday (use both)	
		# (3) if mday = * and wday constained then DO NOT expand mdays but expand wday, ...
		# (4) EXCEPTION: mdays = * and wdays constained with AND(&.). 
		#     In that case, the result is similar to 3 and the 'AND(&.) will be converted to OR within the wday block (e.g.: * * * * 1,&5 will become * * * * 1,5)
		# (5) if mday constrained and wday = * then expand mdays, DO NOT expand wdays
		# - not specified: how to treat lists like *,1 or more weired *,* ? -> treat it as constrained (as in * * 1-31 * 0-6)
		if (($mday eq '*' and $wday eq '*' ) or 
			($mday ne '*' and $wday ne '*' ) or
			($mday ne '*' and $wday eq '*' )) {
			foreach my $item (@list) {
				$self->log(5, 'about to parse mday item: %s', $item) if $ENV{EXTENDED_DEBUG};	
				if (not $self->_parse_mday_item($item, $href)) {
					$self->{error} = "syntax error in mday item: $item";
					$self->log(5, 'syntax error in mday item: %s', $item) if $ENV{EXTENDED_DEBUG};
					return;
				}
			}
		} else {
			$self->log(5, 'ignore mdays because of mday/wday logic') if $ENV{EXTENDED_DEBUG};
		}
		# numerical sort keys and create the list
		@{$self->{list_of_mdays}} = sort { $a <=> $b } keys %$href;
		$self->log(5, 'list_of_mdays: %s', join(',', @{$self->{list_of_mdays}})) if $ENV{EXTENDED_DEBUG};
	}

	{
		my $href = {};
		my @list = split(',', $month);
		foreach my $item (@list) {
			$self->log(5, 'about to parse month item: %s', $item) if $ENV{EXTENDED_DEBUG};
			if (not $self->_parse_month_item($item, $href)) {
				$self->{error} = "syntax error in month item: $item";
				$self->log(5, 'syntax error in month item: %s', $item) if $ENV{EXTENDED_DEBUG};
				return;
			}
		}
		# numerical sort keys and create the list
		@{$self->{list_of_months}} = sort { $a <=> $b } keys %$href;
		$self->log(5, 'list_of_months: %s', join(',', @{$self->{list_of_months}})) if $ENV{EXTENDED_DEBUG};
	}

	{
		my $href_or = {};
		my $href_and = {};
		my @list = split(',', $wday);
		# weired mday/wday logic:
		# (1) if mday = * and wday = * then expand mdays (DO NOT expand wdays) (it would work but it doesnt make sense to use both)
		# (2) if mday constrained and wday constained then expand mdays and wday (use both)	
		# (3) if mday = * and wday constained then DO NOT expand mdays but expand wday, ...
		# (4) EXCEPTION: mdays = * and wdays constained with AND(&.). 
		#     In that case, the result is similar to 3 and the 'AND(&.) will be converted to OR within the wday block (e.g.: * * * * 1,&5 will become * * * * 1,5)
		# (5) if mday constrained and wday = * then expand mdays, DO NOT expand wdays
		# - not specified: how to treat lists like *,1 or more weired *,* ? -> treat it as constrained (as in * * 1-31 * 0-6)
		if (($mday ne '*' and $wday ne '*' ) or
			($mday eq '*' and $wday ne '*' )) {
			foreach my $item (@list) {
				$self->log(5, 'about to parse wday item: %s', $item) if $ENV{EXTENDED_DEBUG};
				# replace weekday abbreviation
				my %w = (Sun => 0, Mon => 1, Tue => 2, Wed => 3, Thu => 4, Fr => 5, Sat => 6);
				$item =~ s/(Sun|Mon|Tue|Wed|Thu|Sat)/$w{$1}/gie;
				
				# RULE 4
				$item =~ s/^[&]//s if ($mday eq '*' and $item =~ m/^[&].*/s);

				my $res = 1;
				$res &&= $self->_parse_wday_item($item, $href_or) if ($item =~ m/^[^&].*/s);
				$res &&= $self->_parse_wday_item($item, $href_and) if ($item =~ m/^[&].*/s);

				if (not $res) {
					$self->{error} = "syntax error in wday item: $item";
					$self->log(5, 'syntax error in wday item: %s', $item) if $ENV{EXTENDED_DEBUG};
					return;
				}
			}
		} else {
			$self->log(5, 'ignore wdays because of mday/wday logic') if $ENV{EXTENDED_DEBUG};
		}
		# numerical sort keys and create the list
		@{$self->{list_of_or_wdays}} = sort { $a <=> $b } keys %$href_or;
		$self->log(5, 'list_of_or_wdays: %s', join(',', @{$self->{list_of_or_wdays}})) if $ENV{EXTENDED_DEBUG};
		@{$self->{list_of_and_wdays}} = sort { $a <=> $b } keys %$href_and;
		$self->log(5, 'list_of_and_wdays: %s', join(',', @{$self->{list_of_and_wdays}})) if $ENV{EXTENDED_DEBUG};
	}
	return 1;
}

# the following pvt functions expect one single list item from the corespondig cron text items, 
# parse it and write the result to a hash_ref with the matching k/v set to 1
# the use of an hash ref is to speed up the list union afterwards to combine different list entries (if)
sub _parse_minute_item {
	my ($self, $in, $href) = @_;
	my ($start, $stop, $step);

	# special treatment if x~x is found: randomize val within given range
	if (my ($lower, $upper) = ($in =~ m/^(0*[0-9]|0*[1-5][0-9])~(0*[0-9]|0*[1-5][0-9])$/)) {
		return if ($lower > $upper); # syntax error
		my $random = $lower + int(rand($upper + 1 - $lower));
		$self->log(5, 'found minute item to randomize: %s, converted to %d', $in, $random) if $ENV{EXTENDED_DEBUG};
		$in = $random;
	}

	($step) = ($in =~ m/\/(0*[1-9]|0*[1-5][0-9])$/);
	($start, $stop) = ($in =~ m/^([*]|0*[0-9]|0*[1-5][0-9])(?:-(0*[0-9]|0*[1-5][0-9]))?(?:\/(?:0*[1-9]|0*[1-5][0-9]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error

	$stop = (defined($step) or ($start eq '*'))?59:$start if (not defined($stop));
	$start = 0 if $start eq '*';
	return if ($start > $stop); # syntax error

	$step //= 1;
	for (my $i = $start; $i <= $stop; $i += $step) {
		$href->{$i} = 1;
	}
	return 1;
}

# hour
sub _parse_hour_item {
	my ($self, $in, $href) = @_;
	my ($start, $stop, $step);

	# special treatment if x~x is found: randomize val within given range
	if (my ($lower, $upper) = ($in =~ m/^(0*[0-9]|0*[1][0-9]|0*2[0-3])~(0*[0-9]|0*[1][0-9]|0*2[0-3])$/)) {
		return if ($lower > $upper); # syntax error
		my $random = $lower + int(rand($upper + 1 - $lower));
		$self->log(5, 'found hour item to randomize: %s, converted to %d', $in, $random) if $ENV{EXTENDED_DEBUG};
		$in = $random;
	}
	($step) = ($in =~ m/\/(0*[1-9]|0*[1][0-9]|0*2[0-3])$/);
	($start, $stop) = ($in =~ m/^([*]|0*[0-9]|0*1[0-9]|0*2[0-3])(?:-(0*[0-9]|0*1[0-9]|0*2[0-3]))?(?:\/(?:0*[1-9]|0*1[0-9]|0*2[0-3]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error

	$stop = (defined($step) or ($start eq '*'))?23:$start if (not defined($stop));
	$start = 0 if $start eq '*';
	return if ($start > $stop); # syntax error
	
	$step //= 1;
	for (my $i = $start; $i <= $stop; $i += $step) {
		$href->{$i} = 1;
	}
	return 1;
}

# day of month
sub _parse_mday_item {
	my ($self, $in, $href) = @_;
	my ($start, $stop, $step);

	($step) = ($in =~ m/\/(0*[1-9]|0*[1,2][0-9]|0*3[0,1])$/);
	($start, $stop) = ($in =~ m/^([*]|0*[1-9]|0*[1,2][0-9]|0*3[0,1])(?:-(0*[1-9]|0*[1,2][0-9]|0*3[0,1]))?(?:\/(?:0*[1-9]|0*[1,2][0-9]|0*3[0,1]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error
		
	$stop = (defined($step) or ($start eq '*'))?31:$start if (not defined($stop));
	$start = 1 if $start eq '*';
	return if ($start > $stop); # syntax error

	$step //= 1;
	for (my $i = $start; $i <= $stop; $i += $step) {
		$href->{$i} = 1;
	}
	return 1;
}

# month
sub _parse_month_item {
	my ($self, $in, $href) = @_;
	my ($start, $stop, $step);

	($step) = ($in =~ m/\/(0*[1-9]|0*1[0-1])$/);
	($start, $stop) = ($in =~ m/^([*]|0*[1-9]|0*1[0-2])(?:-(0*[1-9]|0*1[0-2]))?(?:\/(?:0*[1-9]|0*1[1-2]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error
	
	$stop = (defined($step) or ($start eq '*'))?12:$start if (not defined($stop));
	$start = 1 if $start eq '*';
	return if ($start > $stop); # syntax error
	
	$step //= 1;
	for (my $i = $start; $i <= $stop; $i += $step) {
		$href->{$i} = 1;
	}
	return 1;
}

# wdays expands to 0..6 but accept 0..7 
sub _parse_wday_item {
	my ($self, $in, $href) = @_;
	my ($start, $stop, $step);
	
	($step) = ($in =~ m/\/([1-6])$/);
	($start, $stop) = ($in =~ m/^&?([*]|0*[0-7])(?:-([0-7]))?(?:\/(?:[1-6]))?$/);
	return if (not defined($start) or ($start eq '*' and defined($stop))); # syntax error
	
	$stop = (defined($step) or ($start eq '*'))?6:$start if (not defined($stop));
	$start = 0 if $start eq '*';
	return if ($start > $stop); # syntax error
	
	# adjust for sunday 0 or 7 
	$start %= 7;
	$stop %= 7;

	$step //= 1;
	for (my $i = $start; $i <= $stop; $i += $step) {
		$href->{$i} = 1;
	}
	return 1;
}

# $from_date: date from which the next time is to be determined as yyyymmdd
# $inclusive: TRUE: include from date (>=), FALSE: exclude $from_date (>)
sub _next_date {
	my $self = shift;
	my $from_date = shift; # date
	my $inclusive = shift;

	$self->log(5, 'search next date %s %04d-%02d-%02d', 
		$inclusive?'at or after (inclusive)':'after (exclusive)',
		($from_date =~ m/(\d{4})(\d{2})(\d{2})/)) if $ENV{EXTENDED_DEBUG};

	#  the mdays/months
	if (scalar @{$self->{list_of_mdays}}) { 
		$self->{next_calender_date} = $self->_next_calendar_date($from_date, $inclusive);
	}

	if (scalar @{$self->{list_of_or_wdays}}) {
		$self->{next_weekday_date} = $self->_next_weekday_date($from_date, $inclusive);
	}
	


	$self->{current_work_date} = $self->{next_calender_date};
	#exit(0);

}

sub _next_calendar_date {
	my $self = shift;
	my $from_date = shift; # date
	my $inclusive = shift;

	my ($year, $month, $mday) = ($from_date =~ m/(\d{4})(\d{2})(\d{2})/);

	$self->log(5, 'search next calender date %s %04d-%02d-%02d', 
		$inclusive?'at or after (inclusive)':'after (exclusive)',
		$year, $month, $mday) if $ENV{EXTENDED_DEBUG};

	# initialize ptr or use cached values
	# the ptr points to the correspondig list entry
	$self->{month_ptr} //= sub {
		$self->log(5, 'initialize month pointer') if $ENV{EXTENDED_DEBUG};
		my $i = 0;
		return 0 if ($self->{list_of_months}->[$i] >= $_[0]); 
		while ($self->{list_of_months}->[$i] < $_[0] and $i < $#{$self->{list_of_months}}) {$i++}
		return $i}->($month);
	$self->{mday_ptr} //= sub {
		$self->log(5, 'initialize mdy pointer') if $ENV{EXTENDED_DEBUG};
		my $i = 0;
		return 0 if ($self->{list_of_mdays}->[$i] >= $_[0]); 
		while ($self->{list_of_mdays}->[$i] < $_[0] and $i < $#{$self->{list_of_mdays}}) {$i++} 
		return $i}->($mday);

	$self->log(5, 'pointer set: month %d(%d) mday %d(%d)', $self->{month_ptr}, $self->{list_of_months}->[$self->{month_ptr}], $self->{mday_ptr}, $self->{list_of_mdays}->[$self->{mday_ptr}]) if $ENV{EXTENDED_DEBUG};

	my $found = undef;
	my $year_next = $year;
	while (not defined($found)) {
		my ($y, $m, $d) = ($year_next, $self->{list_of_months}->[$self->{month_ptr}], $self->{list_of_mdays}->[$self->{mday_ptr}]);
		my $candidate = sprintf('%04d%02d%02d', $y, $m, $d);
		$self->log(5, 'test candidate %04d-%02d-%02d', $y, $m, $d) if $ENV{EXTENDED_DEBUG};
		
		# test date is valid (there is no 02-30, and 02-29 only in leap years) and
		# date is greater or equal then the 'from' date (inclusive) or
		# date is greater to the 'from' date (NOT inclusive)
		if ($self->is_valid_date($y, $m, $d) and (
			($inclusive and $candidate >= sprintf('%04d%02d%02d', $year, $month, $mday)) or
			($candidate > sprintf('%04d%02d%02d', $year, $month, $mday)))) {
			# weekdays with 'and' logic			
			if (scalar @{$self->{list_of_and_wdays}}) {
				$self->log(5, 'test candidate %04d-%02d-%02d on wday %d against \'and\' list %s', $y, $m, $d, $self->get_weekday($y, $m, $d), join ',',@{$self->{list_of_and_wdays}}) if $ENV{EXTENDED_DEBUG};
				if (any {$_ == $self->get_weekday($y, $m, $d)} @{$self->{list_of_and_wdays}}) {
					$found = $candidate;
					last;
				}
			} else {
				$found = $candidate;
				last;
			}
		}

		# advance ptr
		$self->{mday_ptr}++;
		if ($self->{mday_ptr} > $#{$self->{list_of_mdays}}) {
			$self->{mday_ptr} = 0;
			$self->{month_ptr}++;
			if ($self->{month_ptr} > $#{$self->{list_of_months}}) {
				$self->{month_ptr} = 0;
				$year_next++;
			}
		}
	}
	$self->log(5, 'found candidate %04d-%02d-%02d', ($found =~ m/(\d{4})(\d{2})(\d{2})/)) if $ENV{EXTENDED_DEBUG};
	return $found;
}

# Input is the date from which the next date is to be determined 
# input array (year, month, mday) 'from'
# return is greater or equal to the input date
sub _next_weekday_date {
	my $self = shift;
	my $from_date = shift; # date
	my $inclusive = shift;

	my ($year, $month, $mday) = ($from_date =~ m/(\d{4})(\d{2})(\d{2})/);

	$self->log(5, 'search next weekday date %s %04d-%02d-%02d', 
		$inclusive?'at or after (inclusive)':'after (exclusive)',
		$year, $month, $mday) if $ENV{EXTENDED_DEBUG};

	# test-candidate year
	my $y = $year;
	# test-candidate month
	# initialize cache if not done already
	if (not defined($self->{month_ptr_wday})) {
		$self->{month_ptr_wday} = first { print "test $#{$self->{list_of_months}} $_ \n"; $self->{list_of_months}->[$_] >= $month } 0 .. $#{$self->{list_of_months}};
		$self->{month_ptr_wday} //= 0; # case month < first entry
	}
	my $m = $self->{list_of_months}->[$self->{month_ptr_wday}];
	$y++ if $m < $month;
	my $d = ($m != $month)?1:$mday;

	printf('first weekday candidate: %4d%02d%02d ptr: %d %s', $y, $m, $d, $self->{month_ptr_wday}, "\n");

	until (($self->{next_weekday_date} // 0) >= sprintf('%4d%02d%02d', $year, $month, $mday)) {
		# weekday of candidate
		my $wday = $self->get_weekday($y, $m, $d);
		# first following upcoming wday from the 'or' list. if the first possible wday < current wday, add one week (7 days)
		my $first = (first {$_ >= $wday} @{ $self->{list_of_or_wdays} }) // $self->{list_of_or_wdays}->[0] + 7;
		# how many days in the future 
		my $day_diff = $first - $wday;
		my $next_wday_in_month = $d + $day_diff;
		printf('candidate %4d%02d%02d is weekday %d - next from \'or_list\' is %d - resulting in day %d %s', $y, $m, $d, $wday, $first, $next_wday_in_month, "\n");
		# if $next_wday_in_month > days in month, advance ptr to next month
		if ($self->is_valid_date($y, $m, $next_wday_in_month)) {
			printf('candidate %4d%02d%02d on weekday %d is a valid date %s', $y, $m, $next_wday_in_month, $first % 6, "\n");
			$self->{next_weekday_date} = sprintf('%4d%02d%02d', $y, $m, $next_wday_in_month);
			# last;
		} else {
			# first day of next available month
			$self->{month_ptr_wday}++;
			if ($self->{month_ptr_wday} > $#{$self->{list_of_months}}) {
				$self->{month_ptr_wday} = 0;
				$y++;
			}
			$m = $self->{list_of_months}->[$self->{month_ptr_wday}];
			$d = 1;
		}
	}
}

sub get_weekday {
	my $self = shift;
	my ($year, $month, $day) = @_;
	# print "wday test $year, $month, $day \n";
	if ($month < 3) {
        $month += 12;
        $year -= 1;
    }

    my $k = $year % 100;
    my $j = int($year / 100);

    # Calculating the day of the week using the Zeller congruence
    my $f = $day + int((13 * ($month + 1)) / 5) + $k + int($k / 4) + int($j / 4) - (2 * $j);
    my $weekday_num = ($f + 6) % 7;  # Modification to get Sunday = 0

    return $weekday_num;
}


# $from_time: time from which the next time is to be determined as hhmmss
# $inclusive: TRUE: include from time (>=), FALSE: exclude $from_time (>)
sub _next_time {
	my $self = shift;
	my $from_time = shift;
	my $inclusive = shift;

	# my ($hour, $minute, $second) = ($from_time =~ m/(\d{2})(\d{2})(\d{2})/);
	$self->log(5, 'search next time %s %02d:%02d:%02d', 
		$inclusive?'at or after (inclusive)':'after (exclusive)',
		($from_time =~ m/(\d{2})(\d{2})(\d{2})/)) if $ENV{EXTENDED_DEBUG};

	my ($hour, $minute, $second) = ($from_time =~ m/(\d{2})(\d{2})(\d{2})/);

	# initialize ptr or use cached values
	# the ptr points to the correspondig list entry
	$self->{hour_ptr} //= sub {
		$self->log(5, 'initialize hour pointer') if $ENV{EXTENDED_DEBUG};
		my $i = 0;
		return 0 if ($self->{list_of_hours}->[$i] >= $_[0]);
		while ($self->{list_of_hours}->[$i] < $_[0] and $i < $#{$self->{list_of_hours}}) {$i++}
		return $i}->($hour);
	$self->{minute_ptr} //= sub {
		$self->log(5, 'initialize minute pointer') if $ENV{EXTENDED_DEBUG};
		my $i = 0; 
		return 0 if ($self->{list_of_minutes}->[$i] >= $_[0]); 
		while ($self->{list_of_minutes}->[$i] < $_[0] and $i < $#{$self->{list_of_minutes}}) {$i++}
		return $i}->($minute);

	$self->log(5, 'pointer set: hour %d(%d) minute %d(%d)', $self->{hour_ptr}, $self->{list_of_hours}->[$self->{hour_ptr}], $self->{minute_ptr}, $self->{list_of_minutes}->[$self->{minute_ptr}]) if $ENV{EXTENDED_DEBUG};

	my ($found, $day_changed) = (undef, undef);	
	while (not defined($found)) {
		my $candidate = sprintf('%02d%02d%02d', $self->{list_of_hours}->[$self->{hour_ptr}], $self->{list_of_minutes}->[$self->{minute_ptr}], 00);
		$self->log(5, 'test candidate %02d:%02d:%02d', ($candidate =~ m/(\d{2})(\d{2})(\d{2})/)) if $ENV{EXTENDED_DEBUG};
		
		if ($inclusive) {
			$found = $candidate if ($candidate >= $from_time or $day_changed);
		} else {
			$found = $candidate if ($candidate > $from_time or $day_changed);
		}

		# need to break here because the pointer increment below trigger a day_changed while advancing.
		last if defined($found);
			
		if (++$self->{minute_ptr} > $#{$self->{list_of_minutes}}) {
			$self->{minute_ptr} = 0;
			$self->{hour_ptr}++;
		};
		# $self->log(5, 'pointer set: hour %d(%d) minute %d(%d)', $self->{hour_ptr}, $self->{list_of_hours}->[$self->{hour_ptr}], $self->{minute_ptr}, $self->{list_of_minutes}->[$self->{minute_ptr}]) if $ENV{EXTENDED_DEBUG};

		if ($self->{hour_ptr} > $#{$self->{list_of_hours}}) {
			$self->{minute_ptr} = 0;
			$self->{hour_ptr} = 0;
			$day_changed = 1;
		};
		# $self->log(5, 'pointer set: hour %d(%d) minute %d(%d)', $self->{hour_ptr}, $self->{list_of_hours}->[$self->{hour_ptr}], $self->{minute_ptr}, $self->{list_of_minutes}->[$self->{minute_ptr}]) if $ENV{EXTENDED_DEBUG};
	}
	
	$self->log(5, 'next time %s %02d:%02d:%02d -> %02d:%02d:%02d %s', 
		$inclusive?'at or after (inclusive)':'after (exclusive)',
		($from_time =~ m/(\d{2})(\d{2})(\d{2})/), 
		($found =~ m/(\d{2})(\d{2})(\d{2})/), 
		$day_changed?'(new day)':'(same day)') if $ENV{EXTENDED_DEBUG};
	return ($found, $day_changed);
}

# Input is the date from which the next date is to be determined 
# input array (year, month, mday) 'from'
# return is greater or equal to the input date
sub _next_special_date {
	my $self = shift;
	my ($year, $month, $mday) = @_;

	printf('next weekday from: %4d%02d%02d %s', $year, $month, $mday, "\n");

	# return if cache has a value

	# test-candidate year
	my $y = $year;
	# test-candidate month
	# initialize cache if not done already
	if (not defined($self->{month_ptr_special})) {
		$self->{month_ptr_special} = first { print "test $#{$self->{list_of_months}} $_ \n"; $self->{list_of_months}->[$_] >= $month } 0 .. $#{$self->{list_of_months}};
		$self->{month_ptr_special} //= 0; # case month < first entry
	}
	my $m = $self->{list_of_months}->[$self->{month_ptr_special}];
	$y++ if $m < $month;
	my $d = ($m != $month)?1:$mday;

	printf('first special date candidate: %4d%02d%02d ptr: %d %s', $y, $m, $d, $self->{month_ptr_special}, "\n");

	# create a list with converted 'special' dates like 0#1 (first sunday in month)
	@{$self->{list_of_special_wdays}} = ('0#5');
	my @list;
	my $href;

	do {

		my $first_wday = $self->get_weekday($y, $m, 1);
		print "special date: first wday of $m is $first_wday \n";

		foreach my $item (@{$self->{list_of_special_wdays}}) {
			print "special item $item \n";
			my ($wday, $number) = ($item =~ m/^([0-6])#([1-6])$/g);
			print "special item: $item = $wday nr $number \n";
			my $day_diff = ($wday + 7 - $first_wday) %7;
			print "special item: day_diff $day_diff \n";
			$day_diff += ($number - 1) * 7;
			$day_diff += 1;
			print "special item: day_diff $day_diff \n";
			if ($self->is_valid_date($y, $m, $day_diff)) {
				printf ("add to list %d %d %d \n", $y, $m, $day_diff);
				push @list, sprintf('%4d%02d%02d', $y, $m, $day_diff);
			}
		}

		# advance ptr
		# first day of next available month
		$self->{month_ptr_special}++;
		if ($self->{month_ptr_special} > $#{$self->{list_of_months}}) {
			$self->{month_ptr_special} = 0;
			$y++;
		}
		$m = $self->{list_of_months}->[$self->{month_ptr_special}];
		$d = 1;
	


	} until (scalar @list)
}

sub is_valid_date {
	my $self = shift;
    my ($year, $month, $day) = @_;

    # Überprüfung der Gültigkeit von Jahr, Monat und Tag
    return 0 if $year < 0 || $month < 1 || $month > 12 || $day < 1 || $day > 31;

    # Liste der Tage pro Monat (ohne Schaltjahre)
    my @days_in_month = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

    # Schaltjahr-Überprüfung
    if ($month == 2 && (($year % 4 == 0 && $year % 100 != 0) || $year % 400 == 0)) {
        $days_in_month[2] = 29;
    }

    # Überprüfung, ob der Tag im gegebenen Monat existiert
    return $day <= $days_in_month[$month];
}


1;