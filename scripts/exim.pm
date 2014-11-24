package exim;

use Gcis::Client;
use strict;
use Data::Dumper;
use YAML;
use v5.14;
use Encode;
use utf8;

local $YAML::Indent = 2;

binmode STDIN, ':encoding(utf8)';
binmode STDOUT, ':encoding(utf8)';

my @item_list = qw (
    base
    report
    chapters
    figures
    images
    tables
    findings
    references
    publications
    journals
    activities
    datasets
    people
    organizations
    files
    );

my $compare_say_same = 0;  # turns on full output (same as well as differences)

sub _unique_uri {
    my $s = shift;
    my $type = shift;
    my $v = shift;
    if (!$s->{$type}) {
        $s->{$type}[0] = $v;
        return 1;
    }
    my $n = 0;
    while (my $uri = $s->{$type}[$n]->{uri}) {
        return 0 if $uri eq $v->{uri};
        $n++;
    }
    $s->{$type}[$n] = $v;
    return 1;
}

sub _update_href {
    my $s = shift;
    my $type = shift;
    my $subtype = shift;

    my $base = quotemeta $s->{base}[0];
    my $n = 0;
    while (my $v = $s->{$type}[$n]) {
        $n++;
        $v->{href}=~ s/^$base/base:/;
        next unless $subtype;
        my $m = 0;
        my $v1 = $v->{$subtype}[$m];
        while (my $v1 = $v->{$subtype}[$m]) {
            $v1->{href} =~ s/^$base/base:/;
            $m++;
        }
    }

    return 0;
}

sub _compare_hash {
    my $s = shift;
    my $a = shift;
    my $b = shift;

    my %v;
    for my $k (keys %$a) {
        next if exists $b->{$k};
        $v{$k} = 'src only';
    }
    for my $k (keys %$b) {
        next if exists $a->{$k};
        $v{$k} = 'dst only';
    }

    my @common_keys = grep exists($b->{$_}), keys %$a;
    for my $k (@common_keys) {

        if (ref $a->{$k} eq 'ARRAY') {
            ref $b->{$k} eq 'ARRAY' or 
                $v{$k} = 'diff - src array, dst not';
            my $comp = $s->_compare_array($k, $a->{$k}, $b->{$k});
            $v{$k} = $comp if $comp;
            next;
        } elsif (ref $b->{$k} eq 'ARRAY') {
            $v{$k} = 'diff - dst array, src not';
            next;
        }

        if (ref $a->{$k} eq 'HASH') {
            ref $b->{$k} eq 'HASH' or
                $v{$k} = 'diff - src hash, dst not';
            my $comp = $s->_compare_hash($a->{$k}, $b->{$k});
            $v{$k} = $comp if $comp;
            next;
        } elsif (ref $b->{$k} eq 'HASH') {
            $v{$k} = 'diff - dst hash, src not';
            next;
        }

        if ($a->{$k} ne encode('utf8',$b->{$k})) {
            $v{$k} = 'diff';
        } else {
            $v{$k} = 'same' if $compare_say_same;
        }
    }

    return %v ? \%v : 0;
}

sub _compare_array {
    my $s = shift;
    my $array = shift;
    my $a = shift;
    my $b = shift;

    my @v;
    my $n_a = @$a;
    my $n_b = @$b;
    return 0 if ($n_a == 0 && $n_b == 0);

    my %id_list = (
        figures => 'uri',
        tables => 'uri',
        findings => 'uri',
        references => 'uri', 
        chapter_uris => '',
        image_uris => '', 
        finding_uris => '',
        file_uris => '',
        publication_maps => 'activity_identifier', 
        parents => 'activity_uri', 
        contributors => 'id',
        sub_publication_uris => '', 
        kindred_figures => '',
        );

    defined %id_list{$array} or die "unknown array type : $array";
    my $id = $id_list{$array};
    if ($id) {
        my %a_objs = map {$_->{$id} => $_} @{ $a };
        my %b_objs = map {$_->{$id} => $_} @{ $b };

        my $m = 0;
        for my $k (keys %a_objs) {
            next if defined $b_objs{$k};
            $v[$m]->{_location} = 'src only';
            $v[$m]->{$id} = $k;
            $m++;
        }
        for my $k (keys %b_objs) {
            next if defined $a_objs{$k};
            $v[$m]->{_location} = 'dst only';
            $v[$m]->{$id} = $k;
            $m++;
        }
        my @common_keys = grep exists($b_objs{$_}), keys %a_objs;
        for my $k (@common_keys) {
            my $comp = $s->_compare_hash($a_objs{$k}, $b_objs{$k});
            $comp or next;
            $v[$m]->{_location} = 'common' if $compare_say_same;
            $v[$m]->{$id} = $k;
            map {$v[$m]->{$_} = $comp->{$_}} keys %$comp;
            $m++;
        }
    } else {
        my %vals;
        for my $i (0..($n_a - 1)) {
            $vals{@$a[$i]} = 'src only';
        }
        for my $i (0..($n_b - 1)) {
            $vals{@$b[$i]} = defined $vals{@$b[$i]} ? 'both' : 'dst only';
        }
        my $m = 0;
        for my $k (keys %vals) {
            next if $vals{$k} eq 'both';
            $v[$m] = "$vals{$k} : $k";
            $m++;
        }
        $v[0] = 'same' if ($m == 0  &&  $compare_say_same);
    }

    return @v ? \@v : 0;
}

sub new {
    my $class = shift;
    my $base = shift;
    my $access = shift;

    my $s;
    if ($base) {
        if ($access eq 'update') {
            $s->{gcis} = Gcis::Client->connect(url => $base);
        } else {
            $s->{gcis} = Gcis::Client->new(url => $base);
        }
    } else {
        $s->{gcis} = 'no url';
    }
    for my $item (@item_list) {
        $s->{$item} = [];
    }
    $s->{base}[0] = $base;
    $s->{all} = '?all=1';

    bless $s, $class;
    return $s;
}

sub not_all {
    my $s = shift;
    $s->{all} = '';
    return 0;
}

sub get {
    my $s = shift;
    my $uri = shift;

    my $v = $s->{gcis}->get($uri);
    return wantarray && ref($v) eq 'ARRAY' ? @$v : $v;
}

sub logger {
    my $s = shift;
    my $logger = shift;

    $s->{gcis}->logger($logger);
    return 0;
}

sub logger_info {
    my $s = shift;
    my $message = shift;
    $s->{gcis}->logger->info($message);
    return 0;
}

sub get_full_report {
    my $s = shift;
    my $uri = shift;

    $s->get_report($uri);
    $s->get_chapters('report');
    $s->get_figures('report');
    $s->get_images('figures');
    $s->get_tables('report');
    $s->get_findings('report');
    $s->get_references('report');
    $s->get_publications('references');
    $s->get_journals('publications');
    $s->get_activities('images');
    $s->get_datasets('activities');

    my @list = qw (
        report
        chapters
        figures
        images
        tables
        findings
        publications
        journals
        datasets
        );
    for my $v (@list) {
        $s->get_contributors($v);
        $s->get_files($v);
    }

    return 0;
}

sub get_report {
    my $s = shift;
    my $uri = shift;
    my $report = $s->get($uri) or die "no report";
    $s->{report}[0] = $report;
    $s->_update_href('report');
    # $report->{summary} = "put summary back in after debug";
    return 0;
}

sub get_chapters {
    my $s = shift;
    my $type = shift;

    my $obj = $s->{$type}[0];
    my $chapters = $obj->{chapters};
    my $n = 0;
    $obj->{chapter_uris} = [];
    for my $chap (@$chapters) {
        my $uri = $chap->{uri};
        my $chapter = $s->get($uri) or die "no chapter";
        $obj->{chapter_uris}[$n++] = $uri;
        $s->_unique_uri('chapters', $chapter);
    }
    delete $obj->{chapters};
    $s->_update_href('chapters', 'figures');
    $s->_update_href('chapters', 'tables');
    $s->_update_href('chapters', 'findings');

    return 0;
}

sub get_figures {
    my $s = shift;
    my $type = shift;

    my $obj_uri = $s->{$type}[0]->{uri}."/figure".$s->{all};
    my @figures = $s->get($obj_uri) or return 1;
    my $n = 0;
    for my $fig (@figures) {
        my $figure = $s->get($fig->{uri}) or die "no figure";
        delete $figure->{chapter};
        $s->{figures}[$n++] = $figure;
    }
    $s->_update_href('figures', 'references');

    return 0;
}

sub get_images {
    my $s = shift;
    my $type = shift;

    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        my $images = $obj->{images};
        my $n_img = 0;
        $s->{$type}[$n_obj]->{image_uris} = [];
        for my $img (@$images) {
            my $uri = "/image/$img->{identifier}";
            my $image = $s->get($uri) or die "no image";
            $s->{$type}[$n_obj]->{image_uris}[$n_img++] = $uri;
            delete $image->{figures};
            $s->_unique_uri('images', $image);
        }
        delete $s->{$type}[$n_obj]->{images};
        $n_obj++;
    }
    $s->_update_href('images');

    return 0;
}

sub get_tables {
    my $s = shift;
    my $type = shift;

    my $obj_uri = $s->{$type}[0]->{uri}."/table".$s->{all};
    my @tables = $s->get($obj_uri) or return 1;
    my $n = 0;
    for my $tab (@tables) {
        my $table = $s->get($tab->{uri}) or die "no figure";
        delete $table->{chapter};
        $s->{tables}[$n++] = $table;
    }
    $s->_update_href('tables', 'references');

    return 0;
}

sub get_findings {
    my $s = shift;
    my $type = shift;

    my $obj = $s->{$type}[0];
    my $obj_uri = $obj->{uri}."/finding".$s->{all};
    my $findings = $s->get($obj_uri) or return 1;
    my $n = 0;
    $obj->{finding_uris} = [];
    for my $find (@$findings) {
        my $uri = $find->{uri};
        my $finding = $s->get($uri) or die "no finding";
        $obj->{finding_uris}[$n++] = $uri;
        delete $finding->{chapter};
        $s->_unique_uri('findings', $finding);
    }
    delete $obj->{findings};
    $s->_update_href('findings', 'references');

    return 0;
}

sub get_references {
    my $s = shift;
    my $type = shift;

    my $obj_uri = $s->{$type}[0]->{uri}."/reference".$s->{all};
    my @references = $s->get($obj_uri) or return 1;
    my $n = 0;
    for my $ref (@references) {
        my $reference = $s->get($ref->{uri}) or die "no reference";
        delete $reference->{chapter};
        $s->{references}[$n++] = $reference;
    }
    $s->_update_href('references');

    return 0;
}

sub get_publications {
    my $s = shift;
    my $type = shift;

    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        if (my $uri = $obj->{child_publication_uri}) {
          my $pub = $s->get($uri) or die "no publication";
          $s->_unique_uri('publications', $pub);
        }
        $n_obj++;
    }
    $s->_update_href('publications', 'references');

    return 0;
}

sub get_journals {
    my $s = shift;
    my $type = shift;

    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        if (my $uri = $obj->{journal_identifier}) {
          my $jou = $s->get("/journal/$uri") or die "no journal";
          $jou->{articles} = [];
          $s->_unique_uri('journals', $jou);
        }
        $n_obj++;
    }
    $s->_update_href('journals');

    return 0;
}

sub get_activities {
    my $s = shift;
    my $type = shift;

    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        my $activities = $obj->{parents};
        for my $act (@$activities) {
            my $uri = $act->{activity_uri} or next;
            my $activity = $s->get($uri) or die "no activity";
            my $pub_maps = $activity->{publication_maps};
            for my $pub_map (@$pub_maps) {
                my $child_uri = $pub_map->{child_uri};
                my $child = $s->get($child_uri) or die "no child";
                $pub_map->{child_uri} = $child->{uri};
                my $parent_uri = $pub_map->{parent_uri};
                my $parent = $s->get($parent_uri) or die "no parent";
                $pub_map->{parent_uri} = $parent->{uri};
            }
            $s->_unique_uri('activities', $activity);
        }
        $n_obj++;
    }
    $s->_update_href('activities');

    return 0;
}

sub get_datasets {
    my $s = shift;
    my $type = shift;

    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        my $pub_maps = $obj->{publication_maps};
        for my $pub_map (@$pub_maps) {
            my $parent_uri = $pub_map->{parent_uri};
            my $parent = $s->get($parent_uri) or die "no parent";
            ($parent->{uri} =~ /^\/dataset\//) or die "parent not a dataset";
            $s->_unique_uri('datasets', $parent);
        }
        $n_obj++;
    }
    $s->_update_href('datasets');

    return 0;
}

sub get_contributors {
    my $s = shift;
    my $type = shift;

    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        my $contributors = $obj->{contributors};
        for my $con (@$contributors) {
            my $org_uri = $con->{organization_uri};
            my $org = $s->get($org_uri) or die "no organizaton";
            delete $con->{organization};
            $s->_unique_uri('organizations', $org);
            if (my $per_uri = $con->{person_uri} ) {
                my $per = $s->get($per_uri) or die "no person";
                delete $per->{contributors};
                $s->_unique_uri('people', $per);
            }
            delete $con->{person};
            delete $con->{person_id};
        }
        $n_obj++;
    }
    $s->_update_href($type, 'contributors');
    $s->_update_href('organizations');
    $s->_update_href('people');

    return 0;
}

sub get_files {
    my $s = shift;
    my $type = shift;

    my @objs = shift;
    my $n_obj = 0;
    while (my $obj = $s->{$type}[$n_obj]) {
        my $files = $obj->{files};
        my $n = 0;
        $obj->{file_uris} = [];
        for my $f (@$files) {
            my $f_uri = $f->{uri};
            $obj->{file_uris}[$n++] = $f_uri;
            my $file = $s->get($f_uri) or die "no file";
            $s->_unique_uri('files', $file);
        }
        delete $obj->{files};
        $n_obj++;
    }
    $s->_update_href('files');

    return 0;
}

sub count {
   my $s = shift;
   my $type = shift;

   my $n = 0;
   while ($s->{$type}[$n]) {
       $n++;
   }
   return $n;
}

sub dump {
   my $s = shift;
   my $file = shift;

   my $e->{base} = $s->{base}[0];
   $e->{report} = $s->{report}[0];
   for my $item (@item_list) {
       $e->{items}->{$item} = $s->count($item);
       next if $item eq 'report';
       next if $item eq 'base';
       $e->{$item} = $s->{$item};
   }

   if (!$file) {
      say Dump($e) or die "unable to export report";
   } else {
      open my $f, '>', $file or die "can't open file";
      say $f Dump($e);
   }

   return;
}

sub load {
    my $s = shift;
    my $file = shift;

    my $e;
    if (!$file) {
       my $yml = do { local $/; <> };
       $e = Load($yml);
    } else {
       open my $f, '<', $file or die "can't open file";
       my $yml = do { local $/; <$f> };
       $e = Load($yml);
    }

    for my $item (@item_list) {
        if (ref($e->{$item}) eq 'ARRAY') {
            $item ne 'report' or die "only one report allowed";
            $item ne 'base' or die "only one base allowed";
            $s->{$item} = $e->{$item};
        } else {
            $s->{$item}[0] = $e->{$item};
        }
    }

    return;   
}

sub compare {
    my $s = shift;
    my $type = shift;
    my $a = shift;
    my $b = shift;

    $s->{base}[0] = {
        src => $a->{base}[0],
        dst => $b->{base}[0]};

    my %a_objs = map {$_->{uri} => $_} @{ $a->{$type} };
    my %b_objs = map {$_->{uri} => $_} @{ $b->{$type} };

    my $n = 0;
    my $v = $s->{$type};
    for my $k (keys %a_objs) {
        next if $b_objs{$k};
        $v->[$n]->{uri} = $k;
        $v->[$n]->{_location} = 'dst only';
        $n++;
    }
    for my $k (keys %b_objs) {
        next if $a_objs{$k};
        $v->[$n]->{uri} = $k;
        $v->[$n]->{_location} = 'src only';
        $n++;
    }

    my @common_keys = grep exists($b_objs{$_}), keys %a_objs;
    for my $k (@common_keys) {
        my $comp = $s->_compare_hash($a_objs{$k}, $b_objs{$k});
        $comp or next;
        $v->[$n]->{uri} = $k;
        $v->[$n]->{_location} = 'common' if $compare_say_same;
        map {$v->[$n]->{$_} = $comp->{$_}} keys %$comp;
        $n++;
    }

    return 0;
}

1;
