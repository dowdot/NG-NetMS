#!/usr/bin/perl -w

#
# Scan subnets which were configured in network
#
# Usage:
#  subnets_scanner.pl [switches] user passwd enpasswd access_type community pass_to_key
#
# Switches:
#  -L        DB host (default:localhost)
#  -D		 DB name
#  -U		 DB User
#  -W 		 Pasword for DB user	
#  -P        DB port
#
#
# Copyright (C) 2015
#
# Author: A.Iaropud
#

use lib "$ENV{'NGNMS_HOME'}/lib/";
use strict;
use threads;
use warnings;

use NGNMS_DB;
use NGNMS_util;
use NGNMS_Linux;
use Data::Dumper;
use Net::Netmask;
use Nmap::Scanner;
use Sort::Key::IPv4 qw(ripv4keysort);

use Emsgd;

logError("subnets_scanner","starting subnet_scanner...");
my $netmask;
my $addr;
my $start;
my $block;
my $counter_int = 0;
my $n;
my $mask;
my %arr;
my $arr_param;
my @nets;
my $b;
my @arr_hmax;
my %blocks0 ;

my $ipaddr;
my $idx;
my $cur_id;
my $ocx_session;
my $os_name;
my $criptokey ;
my $nb_process = 5;
my $type_router;
my $untrust_flag = 0;

## initialize default access to DB
my $dbname 	= '';
my $dbuser 	= '';
my $dbpasswd = '';
my $dbport 	= '5432';
my $dbhost 	= 'localhost';

###################################
# Print debugging output to screen

my $verbose = 0;
$verbose = $ENV{"NGNMS_DEBUG"} if defined($ENV{"NGNMS_DEBUG"});

# Redirect stdout

if ($verbose) {
  # Print debugging output to file

  my $logFile = "/dev/null";
  if (defined($ENV{"NGNMS_LOGFILE"})) {
    $logFile = $ENV{"NGNMS_LOGFILE"};
  }

  open( STDERR, ">&STDOUT") or
    warn "Poll_host failed to redirect STDERR to STDOUT: $!\n";
  open( STDOUT, ">> $logFile") or
    warn "Failed to redirect STDOUT to $logFile: $!\n";
}

print "Subnet_scanner - init variables complete...\n" if ($verbose);
#####################################################################
# Parse command line
#
print "#Debug - Subnet_scanner - parsing arguments...\n" if ($verbose >1);

while (($#ARGV >= 0) && ($ARGV[0] =~ /^-.*/)) {
  
  if ($ARGV[0] eq "-L") {
    shift @ARGV;
    $dbhost = $ARGV[0] if defined($ARGV[0]);
	shift @ARGV;
    next;
  }
  
  if ($ARGV[0] eq "-D") {
    shift @ARGV;
    $dbname = $ARGV[0] if defined($ARGV[0]);
	shift @ARGV;
    next;
  }
  
  if ($ARGV[0] eq "-U") {
	shift @ARGV;
    $dbuser = $ARGV[0] if defined($ARGV[0]);
	shift @ARGV;
    next;
  }
  
  if ($ARGV[0] eq "-W") {
    shift @ARGV;
    $dbpasswd = $ARGV[0] if defined($ARGV[0]);
	shift @ARGV;
    next;
  }

    if ($ARGV[0] eq "-d") {
      $verbose = 1 if ($verbose == 0);  # ignore if already in debug mode via NGNMS_DEBUG variable
      shift @ARGV;
      next;
    }

  if ($ARGV[0] eq "-P") {
    shift @ARGV;
    $dbport = $ARGV[0] if defined($ARGV[0]);
	shift @ARGV;
    next;
	}
	
  if ($ARGV[0] eq "-h") {
	&usage;
    exit;
  }
  shift @ARGV;
}

die "Usage: $0 user passwd access_type [pass_to_key]\n" unless ($#ARGV >= 0);
my ($user, $passwd, $enpasswd, $access,$community,$path_to_key) = @ARGV[0..5];

DB_open($dbname,$dbuser,$dbpasswd,$dbport,$dbhost);
my $arr = DB_getAllIntefaces();

##print Dumper($arr);

my @sorted_keys = ripv4keysort { $arr->{$_}->{ip_addr} } keys %$arr;
my $old_block=new Net::Netmask ('0.0.0.0' , '255.0.0.0');
my $high_link = 4294967295;

for my $key (@sorted_keys) {
            $addr = $arr->{$key}{ip_addr};
		    $netmask = $arr->{$key}{mask};
		    $block = new Net::Netmask ($addr , $netmask);
			my @nets = split /\./, $addr;
#print $addr."\n";
#print Dumper($block);
			if($block->bits() <33)
				{
					
					if(DB_isScanException($block) == 1)
					{
						if($block ne $old_block)
						{
							$blocks0{$counter_int}{block}=$block;
							$blocks0{$counter_int}{high_link}=&ip2num($addr);
							$high_link = &ip2num($addr);
							$old_block = $block;
							$counter_int++;
						}
						else
						{
							if(&ip2num($addr) < $high_link)
							{
								$idx = $counter_int -1;
								$blocks0{$idx}{high_link}=&ip2num($addr);
								$high_link = &ip2num($addr);
							}
						}
					}
				}
}

DB_updateDiscoveryStatus(60,0);
my $p=48;
	$criptokey = DB_getCriptoKey();
	my $length = length $criptokey ;
	$p -= $length; 
	my $suffix =  ( '0' x $p );
	$criptokey.=$suffix;
	my $cmd = "$ENV{'NGNMS_HOME'}/bin/poll_host.pl";

#print Dumper(%blocks0);
DB_close;
    my @block_one = keys %blocks0;
	for my $block_idx (@block_one) {
		print $block_idx.':'.$blocks0{$block_idx}{block}."\n";
	}
	my @threads;
=for	
    for my $block_idx (@block_one) {
    print 	"Scan ".$blocks0{$block_idx}{block}."\n";	
		push @threads, threads->create(\&scansubnet, $blocks0{$block_idx}{block},$blocks0{$block_idx}{high_link});
    }

	foreach my $thread (@threads) {
		$thread->join();
	}
=cut	
my @running = ();
my $block_idx ;
my $old_st = -1;
my $st = 0 ;
my $counter_join = 0;
my $start_bar = 60;
my $pr_bar = 39;
my $int_bar = $#block_one + 1;;
my $step_bar;
my $rest;
my $bar_shift = 0 ;

if($int_bar < $nb_process)
{
	$nb_process = $int_bar;
}

while( $counter_join < $#block_one+1){
	@running = threads->list(threads::running);
	$old_st ++;
	if (scalar @running < $nb_process) {
		$block_idx = $block_one[$st];
		
 		print 	"Scan ".$blocks0{$block_idx}{block}."\n" if($old_st == $st);	
		push @threads, threads->create(\&scansubnet, $blocks0{$block_idx}{block},$blocks0{$block_idx}{high_link});

						$bar_shift++;
						$step_bar = int(($pr_bar * $bar_shift)/$int_bar);
						my $up_percent = $start_bar + $step_bar;
						print "REST1 $bar_shift UPPERCENT:$up_percent.\n";
						DB_open($dbname,$dbuser,$dbpasswd,$dbport,$dbhost);
						my $cur_percent = DB_percentDiscovery();
			
						if($cur_percent <100 && $cur_percent < $up_percent)
						{
							if($up_percent > 99 )
							{
								$up_percent = $cur_percent;
							}
							DB_updateDiscoveryStatus ($up_percent,0);	
						}
						DB_close;
		if ($st < $#block_one)
		{
			$old_st = $st;
			$st++;
		}
	}
	foreach my $thread (@threads) {
		if ($thread->is_running()) {
		}
		elsif ($thread->is_joinable()) {
			$thread->join();
			$counter_join++;
		}
	}
}

DB_open($dbname,$dbuser,$dbpasswd,$dbport,$dbhost);
    my $arr_router_id;
    my $flag ;
    my $control_rout;
    my $count_union;
    my $count_intersect;
	my $arr_hostname = &DB_getDuplicateHostname();
	print Dumper($arr_hostname);
	foreach my $cur_router (@{$arr_hostname})
    {
            $flag = 0;         
            $arr_router_id = &DB_getRouterIdDuplicateHostname($cur_router);
            
            foreach my $rout_id(@{$arr_router_id})
            {
				print $rout_id."\n";
				if($flag == 0)
				{
					$control_rout = $rout_id;
					$flag = 1;
				} 
				else
				{
					$count_union = &DB_getCountUnion($rout_id,$control_rout);
					$count_intersect = &DB_getCountIntersect($rout_id,$control_rout);
					if($count_union == $count_intersect)
					{
						
						&DB_updateLinkA($rout_id,$control_rout);
						&DB_updateLinkB($rout_id,$control_rout);
						&DB_dropRouterId($rout_id);
					}
				}
			}

     }
DB_close;



## Subs to convert dotted-quads to integers and vice versa
sub dq2n{ unpack 'N', pack 'C4', split '\.', $_[ 0 ] };;
sub n2dq{ join '.', unpack 'C4', pack 'N', $_[ 0 ] };;
sub cidrtobin {
   my $cidr = $_[0];
   pack( "B*",(1 x $cidr) . (0 x (32 - $cidr)) );
}
sub getclass {
   my $n = $_[0];
   my $class = 1;
   while (unpack("B$class",$n) !~ /0/) {
      $class++;
      if ($class > 5) {
	 last;
      }
   } 
   return $class;
}
sub getClassNet{
		my ($btmask,$btfb) = @_;
        my $ret_val = 0;
        if($btmask == 8 && $btfb >= 0 && $btfb < 128)
        {
            $ret_val = 1;
        }
        elsif ($btmask == 16 && $btfb>=128 && $btfb <192)
        {
            $ret_val = 1;
        }
        elsif ($btmask == 24 && $btfb>=192 && $btfb <224)
        {
            $ret_val = 1;
        }
        
        return $ret_val;
    }

sub dqtobin {
        my @dq;
	my $q;
	my $i;
	my $bin;

	foreach $q (split /\./,$_[0]) {
		push @dq,$q;
	}
	for ($i = 0; $i < 4 ; $i++) {
		if (! defined $dq[$i]) {
			push @dq,0;
		}
	}
	$bin    = pack("CCCC",@dq);      # 4 unsigned chars
	return $bin;
}
sub bintodq {
	my $dq = join ".",unpack("CCCC",$_[0]);
print 
	return $dq;
}

sub ip2num()
{
	my $ip = $_[0];
	my @a = split /\./,$ip;
    my $intip = int($a[0])*256*256*256+int($a[1])*256*256+int($a[2])*256+int($a[3]); 
    
    return $intip;
	}	
sub num2ip()
{
	my $intip = $_[0];
	my $d = $intip % 256; $intip -= $d; $intip /= 256;
    my $c = $intip % 256; $intip -= $c; $intip /= 256;
    my $b = $intip % 256; $intip -= $b; $intip /= 256;
    my $ip="$intip.$b.$c.$d";
    return $ip;

}




sub scansubnet{
	my ($target,$high_link) = @_;
	my $cur_id ;
	my $cur_ip;
	my $rt_id_parent;
	my $vendor_parent;
	my $control_cur_id;
	my $counter = 0;
	my @upHosts = ();
	my @thrs;

# NMAP system call - modify command line here as needed
#
my $nmap_cmd = "/usr/bin/nmap -T4 -sn -PA22,23,80,443 -oG - $target | /bin/grep Up | /usr/bin/awk '{print \$2}'";
my $fh;
DB_open($dbname,$dbuser,$dbpasswd,$dbport,$dbhost);
    my $id_link = DB_getInterfaceRouterId(&num2ip($high_link));

Emsgd::print 	"NMAP CMD $nmap_cmd";
if (!open($fh, '-|', $nmap_cmd)) {
    Emsgd::print("Nmap epic fail");
    die $!;
    };
# while (my $host = <$fh>) {
#   print 	"\n            ====\n $host \n ==\n";
# }
# return;
while (my $host = <$fh>)

#while (my $host = $host_list->get_next())
	{
		$rt_id_parent = '';
		chomp $host;
		unless (!($host) )
		{
			if( 1 )
			{
				$cur_ip = $host;
#				Emsgd::print "CURIP ".$cur_ip;
				$control_cur_id = DB_getRouterId($cur_ip);
				if(!defined $control_cur_id)
				{
					print "Etap 1\n";
					$cur_id = DB_addRouter($cur_ip,$cur_ip,'unknown');		
					$rt_id_parent = DB_getInterfaceRouterId($cur_ip);
					
					if(!defined $rt_id_parent)
					{		
						print "Etap 1.1\n";	
						$upHosts[$counter]{'addr'} =  $cur_ip;
						$upHosts[$counter]{'high_link'} =  $id_link;
						DB_writeLink($id_link,$cur_id,'B');
						push @thrs, threads->create(\&worker, $cur_ip);
						$counter++;
					}					
					else
					{
						print "Etap 1.2\n";
						## add cheking	        
							
							print "Etap 1.2.1\n";
							$vendor_parent = DB_getRouterVendorById($rt_id_parent);
						
							if(defined $vendor_parent)
							{
								$vendor_parent =~ s/^\s+|\s+$//g;
								DB_setHostVendor($cur_id,$vendor_parent);
							}
							
							$upHosts[$counter]{'addr'} =  $rt_id_parent;
							$upHosts[$counter]{'high_link'} =  $id_link;						
							DB_writeLink($id_link,$rt_id_parent,'B');
						if($untrust_flag){				
							push @thrs, threads->create(\&worker, $cur_ip);						
							$counter++;		
						}
						else
						{
							print "Etap 1.2.2\n";
							DB_dropRouterId($cur_id );
						}		
## end checking						
					}
					
				}
				else
				{
					print "Etap 2\n";
					$rt_id_parent = DB_getInterfaceRouterId($cur_ip);
					
					if(defined $rt_id_parent)
					{
						if($control_cur_id != $rt_id_parent)
						{
							print "Etap 2.1\n";
							$vendor_parent = DB_getRouterVendorById($rt_id_parent);
							print "Vendor:".$vendor_parent."-\n";
							if(defined $vendor_parent)
							{
								$vendor_parent =~ s/^\s+|\s+$//g;
								DB_setHostVendor($control_cur_id,$vendor_parent);
							}
							$upHosts[$counter]{'addr'} =  $rt_id_parent;
							$upHosts[$counter]{'high_link'} =  $id_link;	
							DB_writeLink($id_link,$rt_id_parent,'B');
							push @thrs, threads->create(\&worker, $cur_ip);
							$counter++;
						}
						else
						{
							print "Etap 2.2\n";
							$upHosts[$counter]{'addr'} =  $cur_ip;
							$upHosts[$counter]{'high_link'} =  $id_link;
							DB_writeLink($id_link,$control_cur_id,'B');
							## add cheking	        
							if($untrust_flag){					
								push @thrs, threads->create(\&worker, $cur_ip);
								$counter++;
							}
							## end checking			
						}			
					}
					else
					{
						print "Etap 2.3\n";
						$upHosts[$counter]{'addr'} =  $cur_ip;
						$upHosts[$counter]{'high_link'} =  $id_link;
						DB_writeLink($id_link,$control_cur_id,'B');
						push @thrs, threads->create(\&worker, $cur_ip);
						$counter++;
					}			
				}
			}
		}
	}
		
DB_close;
	
	foreach my $thr (@thrs) {
    $thr->join();
}
	
}	
sub worker
{
	my $ip_addr= shift;
	my @cmd2 = ();
	print "**WORKER** Process ".$ip_addr.":";
	
#	$cur_id = DB_addRouter($ipaddr->{addr},$ipaddr->{addr},'unknown');
#	DB_writeLink($ipaddr->{high_link},$cur_id,'B');
DB_open($dbname,$dbuser,$dbpasswd,$dbport,$dbhost);
	my $amount = DB_isInRouterAccess($ip_addr);
	my @params=();
	$params[0] = $ip_addr; ##host
	$params[0] =~ s/\s+$//; 
DB_close;
		@cmd2=($cmd);

		push @cmd2,'-d';
		push @cmd2,'-L';
		push @cmd2,$dbhost;
		push @cmd2,'-D';
		push @cmd2,$dbname;
		push @cmd2,'-U';
		push @cmd2,$dbuser;
		push @cmd2,'-W';
		push @cmd2,$dbpasswd;
		push @cmd2,'-P';
		push @cmd2,$dbport;
		Emsgd::print(\@cmd2);
		system( @cmd2, @params );
}
sub usage {
    print <<EOF ;
Usage:
  subnets_scanner.pl [switches] user passwd access_type(Telnet/SSH) enpasswd community pass_to_key(if it exist)

  Switches:
   -L       DB host (default:localhost)
   -D       DB name
   -U	 	DB User
   -W		Pasword for DB user
   -P		DB Port
EOF
exit;
}