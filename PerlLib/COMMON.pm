package COMMON;

use strict;
use warnings;
use Carp;

$ENV{LC_ALL} = 'C'; # needed for sorting order.

####
sub get_sort_exec {
    my ($num_threads) = @_;

    # check it like so:
    #  perl -MCOMMON -e 'print COMMON::get_sort_exec(4);'

    my $sort_exec = &find_in_path("sort");
    unless ($sort_exec) {
        confess "Error, cannot find sort utility";
    }

    # probed once; the phase-2 Trinity runs inherit the answer through the environment
    unless (defined $ENV{TRINITY_SORT_HAS_PARALLEL}) {
        my $help_text = `$sort_exec --help`;
        $ENV{TRINITY_SORT_HAS_PARALLEL} = ($help_text =~ m|--parallel|) ? 1 : 0;
    }
    if ($ENV{TRINITY_SORT_HAS_PARALLEL}) {
        ## could do simple versioning check, but I don't remember which version started using parallel
        $sort_exec = "$sort_exec --parallel=$num_threads";
    }
    
    return($sort_exec);
}

####
sub find_in_path {
    my ($prog) = @_;

    # like 'command -v', without forking a shell: phase 2 runs this tens of
    # thousands of times
    if ($prog =~ m|/|) {
        return (-f $prog && -x _) ? $prog : undef;
    }
    foreach my $dir (split(/:/, $ENV{PATH} || "")) {
        next unless length($dir);
        my $path = "$dir/$prog";
        return $path if (-f $path && -x _);
    }
    return undef;
}

1; #EOM
