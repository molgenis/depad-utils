#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use File::Basename;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use CPAN::FindDependencies;

#
# Define additional global vars.
#
my $perl_version = $];
my $perl_modules;		# Input list of Perl Mods for which to report deps.
my @modules;
my @all_deps;
my $basename = basename($0);
my @moduleArray;
my $log_level = 'INFO';	# The default log level.
my %log_levels = (
	'ALL'   => $ALL,
	'TRACE' => $TRACE,
	'DEBUG' => $DEBUG,
	'INFO'  => $INFO,
	'WARN'  => $WARN,
	'ERROR' => $ERROR,
	'FATAL' => $FATAL,
	'OFF'   => $OFF,
);
my $output_format = 'list';
my %output_formats = (
	'list'	=> 'list',
	'eb'	=> 'eb',
);

#
# Get options.
#
Getopt::Long::GetOptions (
	"pm=s" => \$perl_modules,
	"ll=s" => \$log_level,
	"of:s" => \$output_format,
);

#
# Configure logging.
#
# Reset log level to default if user specified illegal log level.
$log_level = (
	defined($log_levels{$log_level})
	? $log_levels{$log_level}
	: $log_levels{'INFO'});
#Log::Log4perl->init('log4perl.properties');
Log::Log4perl->easy_init(
	{
		level  => $log_level,
		file   => "STDOUT",
		layout => '%d L:%L %p> %m%n'
	},
);
my $logger = Log::Log4perl::get_logger();

#
# Parse other inputs.
#
unless (defined($perl_modules) && $perl_modules ne '') {
	_Usage();
	exit 1;
} else{
	@modules = split('\s', $perl_modules);
}

$output_format = (
	defined($output_formats{$output_format})
	? $output_formats{$output_format}
	: $output_formats{'list'});

#
##
### Main.
##
#

foreach my $module (@modules) {
	my @deps = CPAN::FindDependencies::finddeps("$module", 'perl' => $perl_version);
	push(@all_deps, @deps);
}

if ($output_format eq 'list') {
	foreach my $dep (@all_deps) {
		print ' ' x $dep->depth;
		if($dep->warning()) {
			print '! ';
		} else {
			print 'v ';
		}
		print $dep->name, ' [', $dep->distribution(), ']' . "\n";
	}
} elsif ($output_format eq 'eb') {
	my @uniq_deps     = _Uniq(reverse(@all_deps));
	print 'exts_list = [' . "\n";
	foreach my $dep (@uniq_deps) {
		#    ('Text::CSV', '1.33', {
		#        'source_tmpl': 'Text-CSV-1.33.tar.gz',
		#        'source_urls': ['https://cpan.metacpan.org/authors/id/M/MA/MAKAMAKA'],
		#    }),
		
		#Test::Warnings [E/ET/ETHER/Test-Warnings-0.026.tar.gz
		my $module = $dep->name();
		my $distro = $dep->distribution();
		my $archive;
		my $author;
		my $version;
		if ($distro =~ m|(.+)/(([^/]+)-(v?[0-9.]+).tar.gz)$|) {
			$author  = $1;
			$archive = $2;
			$version = $4;
		} else {
			$logger->fatal('Cannot parse module details: ' . $distro);
			exit 1;
		}
		my $url = 'https://cpan.metacpan.org/authors/id/' . $author;
		print '    (\'' . $module . '\', \'' . $version . '\', {' . "\n";
		print '        \'source_tmpl\': \'' . $archive . '\',' . "\n";
		print '        \'source_urls\': [\'' . $url . '\'],' . "\n";
		print '    }),' . "\n";
	}
	print ']' . "\n";
}

#
##
### Subs.
##
#

sub _Uniq {
	my %seen;
	grep(!$seen{$_->name()}++, @_);
}

sub _Usage {
	print STDERR "\n"
	  . 'Usage:' . "\n\n"
	  . '   ' . $basename . ' options' . "\n\n"
	  . 'Available options are:' . "\n\n"
	  . '   -pm \'[PM]\'    Quoted and space sperated list of Perl Modules. E.g. \'My::SPPACE::Seperated List::Of::Modules\'' . "\n"
	  . '   -of [format]  Output Format. One of: list or eb ("exts_list" format for including in an EasyBuild Bundle easyconfig.")' . "\n"
	  . '   -ll [LEVEL]   Log4perl Log Level. One of: ALL, TRACE, DEBUG, INFO (default), WARN, ERROR, FATAL or OFF.' . "\n"
	  . "\n";
	exit;
}
