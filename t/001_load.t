use strict;
use warnings FATAL => 'all';

use Test::More tests => 14;
use Test::TempDatabase;
use POSIX qw(setuid);

BEGIN { use_ok( 'DBIx::VersionedSchema' ); }

unless ($<) {
	diag("Setting postgres uid");
	my $p_uid = getpwnam('postgres');
	setuid($p_uid) or die "Unable to set $p_uid uid";
}

my $temp_db = Test::TempDatabase->create(dbname => 'versioned_schema_db');
ok($temp_db);

my $dbh = $temp_db->handle;
my $vs = DBIx::VersionedSchema->new($dbh);
$vs->Name('hoho_versions');
is($vs->current_version, undef);

$vs->run_updates;
ok($dbh->do('select * from hoho_versions'));
is($vs->current_version, 0);

$vs->run_updates;
is($vs->current_version, 0);

package VSTest1;
use base 'DBIx::VersionedSchema';
__PACKAGE__->Name('vstest_versions');
__PACKAGE__->add_version(sub {
	shift()->do(q{ create table test1 (val text) });
});

package main;
my $vs1 = VSTest1->new($dbh);
is($vs1->current_version, undef);
$vs1->run_updates;
is($vs1->current_version, 1);
ok($dbh->do('select * from test1'));

VSTest1->add_version(sub {
	shift()->do(q{ insert into test1 values ('aaa') });
});
$vs1->run_updates;
is($vs1->current_version, 2);
is(($dbh->selectrow_array(q{ select * from test1 }))[0], 'aaa');

# Test transactioness
VSTest1->add_version(sub {
	shift()->do(q{ insert into test1 values ('bbb') });
});
VSTest1->add_version(sub {
	my $dbh = shift;
	$dbh->do(q{ set client_min_messages to panic });
	$dbh->{PrintError} = 0;
	$dbh->do(q{ insert into shshs values ('aaa') });
});
eval { $vs1->run_updates; };
ok($@);
is($vs1->current_version, 2);
is(scalar($dbh->selectrow_array(q{ 
	select * from test1 where val = 'bbb'})), undef);

