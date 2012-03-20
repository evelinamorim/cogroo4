#!/usr/bin/perl

# This script reads the eval.pl output and create tables that can be used from R, as well
# as an initial R script to generate the table

# expected input:
# 0: the output file from eval.pl
# 1: a comma separated list of attributes that should cause a experiment to be ignored.
#	for example AMA will ignore all experiments with this string sequence.
# 2: a folder name for the output files

package convert_to_r;

use File::Path qw(make_path);
use Cwd 'abs_path';
use Storable qw(freeze thaw);

die "3 arguments required." if(@ARGV != 3);

open IN, $ARGV[0] or die $!;

my @ignore = split(',', $ARGV[1]);
my $folder = $ARGV[2];

my @col;


my $experiment = '';
my %data;
my %table;
my @exp;

foreach my $line (<IN>) {
	if( $line =~ m/===\s+(.*?)\s+===/) {
		putData(\%data, $experiment) if (useData($experiment));
		$experiment = $1;
		undef @col;
		undef %data;
	} elsif( $line =~ m/cutoff/ ) {
		@col = split(/\s+/, $line);
	} elsif($line =~ m/^\d/) {
		my @d = split(/\s+/, $line);
		for(my $i = 0; $i < @col; $i++) {
			my $val = $d[$i];
			if($col[$i] eq 'F-Measure') {
				$val = $val * 100;
				push(@{$data{$col[$i]}}, $val);
			} elsif ($col[$i] eq 'cutoff') {
				push(@{$data{$col[$i]}}, $val);
			} elsif ($col[$i] eq 'model_size') {
				push(@{$data{$col[$i]}}, $val);
			}
			
		}
	}
}
putData(\%data, $experiment) if (useData($experiment));

# the next methods will modify the table, so we better freeze it.
my $storedTable = freeze(\%table);

close IN;

## now we print the tables

my $path = "genGraphics/$folder";
if (-e ($path)) {
}  else {
	make_path($path) || die "Unable to create directory <$!>\n";
 }
 
open CUT, ">$path/cut_f.table";

print CUT "cutoff, " . join(', ', @exp) . "\n";

my @cutoffValues = @{$table{$exp[0]}{'cutoff'}};
my @hNames = generateHumanNames(\@exp);

my %hn;
for(my $i = 0; $i < @hNames; $i++) {
	$hn{$exp[$i]} = $hNames[$i];
}

foreach my $cv (@cutoffValues) {
	print CUT "'$cv', ";
	my @v;
	foreach my $e (@exp) {
		my $fm = shift(@{$table{$e}{'F-Measure'}});
		push(@v, $fm);
	}
	print CUT join(', ', @v);
	print CUT "\n";
}

close CUT;

undef %table;
%table = %{ thaw($storedTable) };


open TEX, ">$path/tex.txt";

	print TEX 
'\begin{table}[h!]
 	\begin{center}
 		{
 		  \setlength{\tabcolsep}{.2em}
    	\begin{tabular}{|r|' . 'c' x @exp . '|}
        	\hline
        	\begin{sideways}Cutoff\end{sideways} & \begin{sideways}' . join('\end{sideways} & \begin{sideways}', @hNames) .'\end{sideways} \\\\ \\hline 
';

# lets mark the maximum values
my %maxF;
my %maxCut;
my $maxGlob = $exp[0];
my $maxGlobCut = 0; #int

foreach my $e (@exp) {
	$maxF{$e} = -1;
	for(my $i = 0; $i < @{$table{$e}{'F-Measure'}}; $i++) {
		if ($maxF{$e} < ${$table{$e}{'F-Measure'}}[$i]) {
			$maxF{$e} = ${$table{$e}{'F-Measure'}}[$i];
			$maxCut{$e} = $cutoffValues[$i];	
		}
	}
	if($maxF{$e} > $maxF{$maxGlob}) {
		$maxGlob = $e;
		$maxGlobCut = $maxCut{$e};
	}
}

foreach my $cv (@cutoffValues) {
	print TEX "        	$cv & ";
	my @v;
	foreach my $e (@exp) {
		my $fm = shift(@{$table{$e}{'F-Measure'}});
		my $pref = '';
		my $suf = '';
		if($maxCut{$e} eq $cv) {
			$pref = '\\textbf{' . $pref;
			$suf = $suf . "}";
		}
		if($e eq $maxGlob && $maxGlobCut eq $cv) {
			$pref = '\\underline{' . $pref;
			$suf = $suf . "}";
		}
		push(@v, sprintf("$pref%.2f$suf", $fm));
	}
	print TEX join(' & ', @v) . "\\\\ \n";
}

	print TEX 
'        \hline
    	\end{tabular}
   \caption{TODO}
   \label{tb:TODO}
	}
	\end{center}
\end{table}';

close TEX;


undef %table;
%table = %{ thaw($storedTable) };

open COM, ">$path/complete.table";

print COM "exp, cut, f, size, nn\n";

foreach my $e (@exp) {
	while(@{$table{$e}{'F-Measure'}} > 0) {
		my $ct = shift(@{$table{$e}{'cutoff'}});
		my $fm = shift(@{$table{$e}{'F-Measure'}});
		my $s = shift(@{$table{$e}{'model_size'}});
		print COM "$e, $ct, $fm, $s, '$hn{$e}'\n";
	}
}

close COM;

undef %table;
%table = %{ thaw($storedTable) };

open SIZE, ">$path/size_f.table";

print SIZE "exp, f, size, cutoff\n";
foreach my $e (@exp) {
	my $ct = -1;
	my $maxFm = -1;
	my $s = -1;
	while(@{$table{$e}{'F-Measure'}} > 0) {
		my $fm = shift(@{$table{$e}{'F-Measure'}});
		if($fm > $maxFm) {
			$maxFm = $fm;
			$ct = shift(@{$table{$e}{'cutoff'}});
			$s = shift(@{$table{$e}{'model_size'}});	
		}
	}
	print SIZE "$e, $maxFm, $s, $ct\n";
}

close SIZE;

# Now we can create the R script :)


open R, ">$path/graphics.R";

print R "library(ggplot2)\n\n";

# get path
my $baseNameCut = abs_path("$path/cut_f.table");
my $baseNameCom = abs_path("$path/complete.table");
my $baseNameSize = abs_path("$path/size_f.table");
my $baseNameCutGraphic = abs_path("$path/cut_f-graphic.pdf");
my $numExp = @exp;
my $numCuttoff = @cutoffValues;

# import tables
print R "comp <- read.table(\"$baseNameCom\", header=T, sep=\",\")\n";
print R "cut_f <- read.table(\"$baseNameCut\", header=T, sep=\",\")\n";
print R "size_f <- read.table(\"$baseNameSize\", header=T, sep=\",\")\n\n";

# experiment names
#print R "names <- c('" . join("',\n'", @hNames) . "')\n\n";

#for (my $i = 0; $i < @hNames - 1; $i++) {
#	print R "'$exp[$i]'='$hNames[$i]',\n";	
#}
#print R "'$exp[@hNames-1]'='$hNames[@hNames-1]'\n";

# calc range
my $range = "cut_f[2:" . ($numExp + 1) . "]";
print R "g_range <- range(max(min($range),max($range) - 10), max($range))\n\n";

# lines, points and colors...
print R "color_plot = sample(rainbow($numExp))\n";
print R "lty_plot <- c(1:$numExp)\n";
print R "pch_plot <- c(seq(18,25),seq(0:18))\n\n";

# plot using ggplot2

#print R "ggplot(data=cut_f, aes(x=1:$numCuttoff, y=$exp[0], group=names[1], colour=names[1])) + geom_line() + geom_point()";

	print R << "EOF";
p <- ggplot(data=comp, aes(x=1:$numCuttoff, y=f, group=nn, shape=nn, colour=nn)) +
	geom_line(aes(linetype=nn), size=1) +     # Set linetype by experience
	geom_point(size=3, fill="white") +         # Use larger points, fill with white
	ylim(max(min(comp\$f),max(comp\$f)-10), max(comp\$f)) +      # Set y range
	scale_colour_hue(name="Experiments", 	   # Set legend title
		l=30)  +                  # Use darker colors (lightness=30)
	scale_shape_manual(name="Experiments", values=c(1:25)) +      # Use points with a fill color
	scale_linetype_discrete(name="Experiments") +
	xlab("Cutoff") + ylab(expression(F[1] * " (\%)")) + # Set axis labels
	scale_x_discrete(breaks=1:$numCuttoff, labels=cut_f\$cutoff) +
	theme_bw() +
	opts(legend.direction = "horizontal", 
		legend.position = "bottom", 
		legend.box = "vertical", 
		legend.title.align = 0, 
		legend.background = theme_rect()) +
	guides(col=guide_legend(ncol=2))

p
ggsave(p, file="$baseNameCutGraphic")


EOF


# plot points chart

	print R << "EOF";
ggplot(data=size_f, aes(x=size, y=f, shape=nn, colour=cutoff)) +
	geom_point(size=3, fill="white") +
	scale_shape_discrete(name="Experiments") +
	scale_colour_hue(name="Cutoff", 	   # Set legend title
		l=30)



EOF



# 

# the plot
# print R "plot(cut_f\$$exp[0],\ttype='o', pch=pch_plot[1], lty=lty_plot[1], col=color_plot[1], ylim=g_range, axes=FALSE, ann=FALSE)\n";
#for(my $i = 1; $i < @exp; $i++) {
#	my $p1 = $i + 1;
#	print R "lines(cut_f\$$exp[$i],	type='o', pch=pch_plot[$p1], lty=lty_plot[$p1], col=color_plot[$p1])\n";
#}



# legend
#print R "\nlegend('bottomleft', names, cex=0.8, lty=lty_plot, col=color_plot, pch=pch_plot, lwd=2, bty='n');\n";

#print R "axis(1, at=1:" . @cutoffValues . ", lab=cut_f\$cutoff)
#axis(2)
#box()
#title(xlab='Cutoff')
#title(ylab='F-Measure (%)')
#";

close R;

sub useData {
	my $exp = shift;
	if($exp eq '') {
		return 0;
	}
	foreach my $ig (@ignore) {
		$ig = quotemeta($ig);
		if($exp =~ /\b$ig\b/) {
			return 0;
		}
	}
	return 1;	
}

sub putData {
	my %theData = %{$_[0]};
	my $id = processName( $_[1] );
	$table{$id} = \%theData;
	push(@exp, $id);
}

sub processName {
	my $name = shift;
	$name =~ s/([-,])SD_/$1/g;
	$name =~ s/-gp$//g;
	$name =~ s/-ap$//g;
	$name =~ s/_//g;
	$name =~ s/,/./g;
	$name =~ s/-/./g;
	return $name;
}

sub generateHumanNames {
	my @names = @{$_[0]};
	# we need to create a copy of it...
	my $store = freeze(\@names);
	@names = @{ thaw($store) };
	
	# replace dots
	for(my $i = 0; $i < @names; $i++) {
		$names[$i] =~ s/\./ /g;
	}
	
	# now we look for common parts to remove.
	if(@names > 0) {
		my @parts = split(/\s+/,$names[0]);
		foreach my $p (@parts) {
			my $isCommon = 1;
			$p = quotemeta($p);
			for(my $i = 1; $i < @names; $i++) {
				if($names[$i] !~ m/\b$p\b/) {
					$isCommon = 0;
				}
			}
			if($isCommon) {
				for(my $i = 0; $i < @names; $i++) {
					$names[$i] =~ s/\b$p\b//g;
				}
			}
		}
	}
	
	for(my $i = 0; $i < @names; $i++) {
		$names[$i] =~ s/NONE//g;
		$names[$i] =~ s/^\s+//g;
		$names[$i] =~ s/\s+$//g;
		$names[$i] =~ s/\s+/ /g;
		$names[$i] = uc($names[$i]);
	}
	
	return @names;
}