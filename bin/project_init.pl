#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Module::Find;
use IO::File;
use Data::Dumper;
use File::Path qw(make_path remove_tree);
use File::Touch;
use Git::Repository;
use Net::GitHub;
use Net::GitHub::V2::Repositories;
use Config::Auto;


use Buckley::PrimerDesigner;

# for testing
use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };


######
# Parse Command Line Arguments

my (
    $verbose, 
    $project_name,
    $github_user,
    $github_token,
    $help
   );

my $project_description = '';
my $project_url = '';
my $project_is_public = 1;

my $result = GetOptions (
			 "project_name=s"        => \$project_name,
			 "project_description=s" => \$project_description,
			 "project_url=s"         => \$project_url,
			 "project_is_public"     => \$project_is_public,
			 "github_user=s"         => \$github_user,
			 "github_token=s"        => \$github_token,
			 "verbose"               => \$verbose,
			 "help|h"                => \$help,    
 		     );


if($help){
    print "\nproject_init --project_name my_project\n\n";
    exit 0;
}

die "Please provide a project name" unless $project_name;


#create the directory structure
die "Project directory already exists" if -e $project_name;
make_path("$project_name/data", "$project_name/results", "$project_name/scripts");
touch ("$project_name/SNAPID", "$project_name/VOLUMEID");


# README file
my $fh = IO::File->new("> $project_name/README");
if (defined $fh) {
    print $fh "Describe your project here\n";
    $fh->close;
}


# Capfile - probably change this to something else at some point. 
# Maybe to fit with the job scheduler, monitor, thingy.
$fh = IO::File->new(">  $project_name/Capfile");
if (defined $fh) {
    print $fh qq|
require 'catpaws'
#generic settings
set :aws_access_key,  ENV['AMAZON_ACCESS_KEY']
set :aws_secret_access_key , ENV['AMAZON_SECRET_ACCESS_KEY']
set :ec2_url, ENV['EC2_URL']
set :ssh_options, { :user => "ubuntu", :keys=>[ENV['EC2_KEYFILE']]}
set :key, ENV['EC2_KEY']
set :key_file, ENV['EC2_KEYFILE']
set :ami, '' 
set :instance_type, ''
set :working_dir, '/mnt/work'
set :nhosts, 1
set :group_name, ''
set :snap_id, `cat SNAPID`.chomp 
set :vol_id, `cat VOLUMEID`.chomp 
set :ebs_size, 10 
set :availability_zone, 'eu-west-1a'
set :dev, '/dev/sdf'
set :mount_point, '/mnt/data'


#make a new EBS volume from this snap 
#cap EBS:create

#and mount your EBS
#cap EBS:attach
#cap EBS:mount_xfs

#if you want to keep the results

#cap EBS:snapshot


#and then shut everything down:

# cap EBS:unmount
# cap EBS:detach
# cap EBS:delete - unless you're planning to use it again.
# cap EC2:stop

    |;
    $fh->close;
}

## Add a default .gitignore file
$fh = IO::File->new(">  $project_name/.gitignore");
if (defined $fh) {
    print $fh qq|
*~
*#
*.swp
results*
data/*
Capfile.local
*nohup*
*.htaccess*
	|;
    $fh->close;
}

## And a default .htaccess file that gives access to users
## in the buckley group? Is this wise?
$fh = IO::File->new("> $project_name/.htaccess");
if (defined $fh){
  print $fh qq|
Order allow,deny
Allow from all
AuthName "$project_name"
AuthType Basic
AuthUserFile /etc/htpasswd/.htpasswd
require user buckleylab
Options Indexes
|;
  $fh->close;
}

unless ($github_user && $github_token){
    if (-e "$ENV{HOME}/.gitconfig"){
	my $config = Config::Auto::parse("$ENV{HOME}/.gitconfig", format => "ini");
	die "No github settings found in .gitconfig" unless $config->{github};
	$github_user = $config->{github}->{user};
	$github_token = $config->{github}->{token};
    }
    else{
	die "No github_user and github_token given and ~/.gitconfig not found" 
	}
}

## Make this a git repository.
my $r = Git::Repository->create( init => $project_name );

#and change dir into that repos
chdir($project_name) or die "can't cd into $project_name";

# add the skeleton files
$r->run( add => '.' );
$r->run( commit => '-m', 'Project Skeleton Creation' );

# make a github repos to go with it
my $repos = Net::GitHub::V2::Repositories->new(
					       owner => $github_user,
					       repo  => $project_name ,
					       login => $github_user, 
					       token => $github_token,
					       );

my $remote_r = $repos->create( $project_name, $project_description, $project_url, $project_is_public );


# run commands to setup remote repos.
my $res = $r->run('commit', { 'm' => 'Project Skeleton Created' });


# can't get this to work via Git::Repository. Will see if I can do it at some point, 
# but for now:
my $cmd = 'git remote add origin git@github.com:'.$github_user.'/'.$project_name.'.git';
`$cmd`;
`git push -u origin master`;


