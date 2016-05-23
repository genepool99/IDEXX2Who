#!/usr/bin/perl
use strict;
use warnings;
use XML::LibXML;

#########################################################################################
#		Name: 		Idexx2Whonet3.pl													
#		Version:	3.1.2																
#		Date:		  11.04.11															
#		By:			  Avi Solomon															
#		Purpose: 	Convert idexx "import" xml to a format suitable for WhoNet			
#		Requires: Idexx xml file														
#		Input:		commandline arg filename.xml and outputfile.tsv						
#		Output:		TSV text file and standard output debug								
#########################################################################################

my $startTime = time();													    # Time script started
my $debugMode = 0;														      # (0|1) 1=turn on debug mode
my $printMode = 0;														      # (0|1) 1=print to screen
my $printHeader = 1;													      # 1= turn off header printing to file
my $excludeResults = 0;													    # (0|1|2) 0=exclude none, 1=exclude negitive, 2=
my $XMLfile;
my $TXTfile;

if ($#ARGV < 1){														        # Check for the min number of commandline args
	printHelp("Error: Too few arguments.");						# If wrong number print the help screen
	exit 0;																            # then exit
}
foreach(@ARGV){
	if ($_ eq "-d"){
		$debugMode = 1;
	}
	elsif ($_ eq "-s"){
		$printMode = 1;
	}
	elsif ($_ eq "-En"){
		$excludeResults = 1;											      # exclude negitive results
	}
	elsif ($_ eq "-Nh"){
		$printHeader = 1;												        # exclude negitive results
	}
	elsif (($_ =~ m/.txt/) or ($_ =~ m/.tsv/)){
		$TXTfile = $_;													        # path to file to write
		open(OUTP, ">$TXTfile") or die("Error can not open ", $TXTfile, " to write!");
	}
	elsif ($_ =~ m/.xml/){
		$XMLfile = $_;													        # path of XML file from idexx
	}
	else {
		printHelp("Error: Unknown command line argument.");				# If wrong number print the help screen
		exit 0;
	}
}
if (!$XMLfile){
	printHelp("Error: Missing XML File.");
	exit 0;
}
if (!$TXTfile and ($printMode == 0)){
	printHelp("Error: Missing text file to write too.");
	exit 0;
}
my $parser = XML::LibXML->new();										    # create a new instance of LibXML 
my $tree = $parser->parse_file($XMLfile);								# tree now points the the "top" of the XML file
if(! $tree ){
	print "Error can not open ", $XMLfile, " for reading!";
	exit 0;
}

# Build an array of the UnitCode Ext-ID's that are cultures
# add to this list for future idexx culture codes
my @cultureID = 	(	
					400, 401, 414, 417, 427, 432, 435, 
					437, 2503, 2781, 3040, 4011, 4027,
					4033, 4035, 4183, 6030, 40127
					);
my @testCodeCounts;														  # count how many of each test code was used

# Get the lab and clinic data that is true for all the accessions 
my ($clinicAccountNumber, $clinicName) = parseClinic($tree);
my ($labIDNumber, $labName) = parseLab($tree);

parseAccessions($tree);													# Start the parsing of all the accessions

if($printMode == 0){
	close(OUTP);														      # Close the file we wrote too
}

print "Test Code:\tCount:\n";
for (my $i = 0; $i<50000; $i++){
	if($testCodeCounts[$i]){
		print $i, "\t\t",$testCodeCounts[$i],"\n";
	}
}

my $endTime = time();													# Time processing xml finished
print "Total processing time:\t\t", ($endTime-$startTime), " seconds.\n";	
print "Idexx2Who v.3.1, Avi Solomon (asolomon\@dovelewis.org), 2011 \n\n";								

# Loop through each accession 
sub parseAccessions {
	my $accessionTree = $_[0];											  # passed pointer to location in tree
	my $totalCultures = 0;												    # total cultures counter
	my $totalNegCultures = 0;											    # negitive cultures counter
	my $totalSuscep = 0;												      # total sensitivies counter
	my $totalCulturesCancelled = 0;										# total canceled culture results (ignored by parcer)
	my $totalSuscepCancelled = 0;										  # total canceled susceptibilities canceled (ignored by parcer)
	my $totalNonFinalResults = 0;										  # total results that were not finialized (ignored by parcer)
	my $totalIsolates = 0;												    # total Isolates
	if($printMode == 0){
		printHeader();													        # print the header for the text file
	}
	my $debugCounter = 1;												      # counts the Accessions parsed prints during debug output
	my $errorEnc = 0;													        # throw flag if error was encountered
	foreach my $accession ($accessionTree->findnodes('/LabReport/Accession')){	# loop through the LabData->Accession(s)
		my($status) = $accession->getAttribute("Order-Status");			# get the status of the accession
		my $accCultures = 0;											      # Count of the cultures in this accession
		my $accSuscep = 0;												      # Count of the susceptibilities in this accession
		my $negResults = 0;												      # Total count of negitive results for given accession
		my $source = "Unknown";											    # The source of a given culture (default:Unknown)
		my @isolates;													          # An array of hashes of the culture isolates for a given accession
		my @sens;														            # array of hashes of all the non-cancelled sensitivities
		my $header = {};												        # a hash that holds the assession header data
		if ($status eq "F"){											      # make sure the status is FINAL or ignore the unit
			$header = parseAccessionHeader($accession);					# store header data in an array
			foreach my $unit ($accession->findnodes('./UnitCode')){		# Loop through the Accession units
				my $unitType = parseUnitType($unit);					# use parse unit type to find out if I care about this unit
				if ($unitType eq 1){									        ## unit is a culture result ##							
					my ($cancelled, $unitTotal, $numOfNeg, $unitSource, @unitIsolates) = parseCultureResults($unit);
					if ($cancelled != 1){								        # make sure this unit has not been canceled before processing
						$accCultures = $accCultures + $unitTotal; 		# add to the accession culture counter
						$totalCultures = $totalCultures + $unitTotal;	# add to the total cultures counter
						$negResults = $negResults+$numOfNeg;			# add to the accession negitive results counter
						$totalNegCultures = $totalNegCultures+$numOfNeg;# add to the total negitive results counter
						foreach (@unitIsolates){						      # for each isolated organism split the growth from the organism and store them
							print "ISO: ",$_,"\n";
							## SPECIAL IDEXX BUGFIXES ##
							$_ =~ s/\s\(unable to speciate\)//i;
							$_ =~ s/- unable to speciate//i;	
    						$_ =~ s/ - Coagulase Positive/ Coagulase Positive/i;
    						$_ =~ s/ - Coagulase Negative/ Coagulase Negative/i;
    						$_ =~ s/  / /;
    						$_ =~ s/- ISOLATED FROM THIO//;
    						$_ =~ s/-  ISOLATED FROM//;
    						$_ =~ s/ISOLATED FROM THIO//;
    						$_ =~ s/NON-ENTERIC GRAM NEG RODS/NON-ENTERIC GRAM NEGATIVE ROD/;
    						$_ =~ s/NON-ENTERIC GRAM NEG ROD/NON-ENTERIC GRAM NEGATIVE ROD/;
    						$_ =~ s/- -/-/;
    						$_ =~ s/-$//;
							##
							my @splitIso = split(/\s-\s/, $_, 2);
							if($splitIso[1]){
								push @isolates, {ORGANISM=>$splitIso[0], GROWTH=>$splitIso[1]};
							}
							else {
								push @isolates, {ORGANISM=>$splitIso[0], GROWTH=>" "};
							}
						}
						$source = $unitSource;
					}
					else{$totalCulturesCancelled++;}					  # increment the total canceled results counter	
				}
				elsif ($unitType eq 2){									## unit is a sensitivity ##							
					my ($cancelled, $organism, @results) = parseSensResults($unit);
					if($cancelled != 1){								        # make sure the unit is not cancelled results
						## SPECIAL IDEXX BUGFIXES ##
						$organism =~ s/NON-ENTERIC NEG ROD/Non-enteric gram negative rod/;
						$organism =~ s/Non-enteric gram negative rod /Non-enteric gram negative rod/;
						$organism =~ s/Serratia marcesens/Serratia marcescens/;
						$organism =~ s/ - Coagulase Positive/ Coagulase Positive/i;
						$organism =~ s/ - Coagulase Negative/ Coagulase Negative/i;
						$organism =~ s/ - UNABLE TO SPECIATE//i;
						$organism =~ s/\(UNABLE TO SPECIATE\)//i;
						##
						# split the organism from the growth the new way 
						my @splitOrg = split(/(\n|GREATER|FEW|\d\d,\d\d\d|\d,\d\d\d|\d+\+|Isolated from THIO broth|URINE SUBMITTED ON SWAB, UNABLE TO QUANTITATE)/, $organism);	
						
						if ($debugMode == 1){
							foreach(@splitOrg){
								print "SPLIT ORG:", $_,"\n";
							}
						}
						if ($splitOrg[1]){								  # if there is a growth record
							chomp(@splitOrg);							    
							my $OrgTemp = $splitOrg[0];				# Save the first element, the org
							$splitOrg[0] = "";							 
							my $growthTemp = join "", @splitOrg;
							push @sens, {ORGANISM=>$OrgTemp,GROWTH=>$growthTemp,RESULTS=>[@results]};
						}
						else{
							if ($debugMode == 1){
								print "DEBUG: NO GROWTH DATA\n";
							}	
							push @sens, {ORGANISM=>$splitOrg[0],GROWTH=>" ",RESULTS=>[@results]};										
						}
						$totalSuscep++; $accSuscep++;					  # increment the positive suscep counters
					}
					else {$totalSuscepCancelled++;}						# increment the cancelled suscep counter
				}
			}	
		}
		else {$totalNonFinalResults++;}									# increment the non-final results counter
		
		if ($debugMode == 1){										      	# if we are in debug mode print some useful info
			print "-------------------------------------\n";
			print "Accession: ",$debugCounter,"\n";
			$debugCounter++;
			print "Accession Parsed\n \tCultures:",$accCultures, 
			"\n\tSusceptabilities:", $accSuscep, "\n\tNegitives:", $negResults,"\n"; 
			my $cultures = 0;
			my $susceps = 0;
			foreach(@isolates){
				$cultures++;
				print "Culture Isolate:\t", $_->{ORGANISM};
				print "\tGrowth: ", $_->{GROWTH}, "\n";
			}
			foreach(@sens){
				$susceps++;
				print "Sens Isolate:\t\t", $_->{ORGANISM},"\tGrowth: ",$_->{GROWTH}, "\n";
			}
			if($cultures == 0 && $susceps > 0){
				print "***** ERROR DATA CONST ISSUE ***** \n";
				$errorEnc = 1;
			}
			print "______DATA______\n";
		}
		
		if($excludeResults == 0)										        # if we are printing negitive results
		{
			for (my $i = 0; $i<$negResults; $i++){						# for each negitive result print just header line 
				printLine($printMode,$header,$source);	
			}
		}	
		
		foreach(@isolates){												          # loop through the cultured isolates
			my $currentIso = $_->{ORGANISM};
			my $currentGrowth = $_->{GROWTH};
			my $dontPrint = 0;
			foreach(@sens){												            # loop through the organisms with sensitivities
				my $currentSensIso = $_->{ORGANISM};
				if($currentIso =~ /$currentSensIso/i){					# if a sensitivity is done on this organism
					$dontPrint = 1;										            
				}
				elsif($currentIso eq $currentSensIso){
					$dontPrint = 1;
				}
			}
			if($dontPrint eq 0){
				printLine($printMode, $header, $source, $currentIso, $currentGrowth);	# if no sensitivity was done print culture
				$totalIsolates++;
			}
		}
		foreach(@sens){
			printLine($printMode, $header, $source, $_->{ORGANISM},$_->{GROWTH}, $_);	# print the sensitivities done
			$totalIsolates++;
		}		
	} 
	if($errorEnc == 1){
		print "Warning: An error was found in the data processing.  Check the debug output.\n";
	}
	print "\nProcessing of ", $XMLfile, " is complete.\n";
	print "Total Isolates: \t\t", $totalIsolates, "\n";
	print "Total Cultures Found:\t\t",$totalCultures, "\n";
	print "Total Negative Cultures:\t", $totalNegCultures, "\n";
	print "Total Susceptibilities:\t\t",$totalSuscep, "\n";
	print "Ignored (CANCELLED) Cultures:\t", $totalCulturesCancelled, "\n";
	print "Ignored (CANCELLED) Suscep.:\t", $totalSuscepCancelled, "\n";
	print "Ignored (Non-Final) Results:\t", $totalNonFinalResults, "\n"; 
}

# Parse and return sensitivity data
# Return Data: (0|1) Cancelled, Organism with value, Anitbiotic with value
sub parseSensResults {
	my $unit = $_[0];													
	my $organism = "Unknown";											# organism sens was done on, default:Unknown
	my @results;														      # results of the sens
	foreach my $testCode ($unit->findnodes('./TestCode')){				# loop through the testcodes in this unit
    	my($TCextID) = $testCode->getAttribute("Ext-ID");
    	my($TCstatus) = $testCode->getAttribute("Status");
    	my($TCname) = $testCode->findnodes('Name');
    	my($TCvalue) = $testCode->findnodes('Value');
    	my($TCcomment) = $testCode->findnodes('Comment');
    	if($TCvalue->to_literal eq "CANCELLED"){						# if anything in this test was cancelled 
    		return (1, $organism, @results);							    # break with cancelled return value
    	}
    	if ($TCname->to_literal eq "ORGANISM"){
    		$organism = $TCcomment->to_literal;							  # split the orginism from the growth value	
    	}
    	else{
    		push(@results, $TCname->to_literal);						  # add the anitbiotic to @results
    		my @values = split(" ", $TCvalue->to_literal);		# split the anitbiotic from the resistance and MIC
    		if ($values[0]){
    			push(@results, $values[0]);								      # add the restance to @results
    		}
    		else {
    			push(@results, " ");									          # if no R/I/S Result exists add a placeholder to @results
    		}
    		
    		if($values[1]){												            # if a value for MIC exists
    			push(@results,$values[1]);								      # add MIC to @results
    		}
    		else {
    			push(@results, " ");									          # if no MIC exists add a placeholder to @results
    		}
    	}
    }
    return (0, $organism, @results);
}

# Parse and return the culture results.
# Return Data: (0|1) Canceled, Number of negitive, Source, Isolates with value
sub parseCultureResults {
	my $unit = $_[0];													              # passed pointer to unit
	my $source = "Unknown";												          # culture source Default:Unknown
	my $negResults = 0;													            # number of negitive cultures in this unit
	my $totalCultures = 0;												          # count of the number of culture results found
	my @isolates;														                # array of orginisms isolated in this unit
	
	foreach my $testCode ($unit->findnodes('./TestCode')){				# loop through each testcode in the unit
		my($name) = $testCode->findnodes('Name');						  
		my($value) = $testCode->findnodes('Value');						
		if($value->to_literal eq "CANCELLED"){							  # if this test was canceled
			return (1, 0, $source, @isolates);							    # return 1 in the canceled field exiting the parcer
		}
		elsif ($name->to_literal eq "SOURCE:"){							  # if this is the source test code
			$source = $value->to_literal;								        # if a source is found store it's value
		}
		elsif (($name->to_literal eq "COMPLETED CULTURE RESULTS") or ($name->to_literal eq "ANAEROBIC RESULTS:")){
			$totalCultures++;											# found a culture result, increment counter
			my($comment) = $testCode->findnodes('Comment');				
			my @commentLines = split(/\n/,$comment->to_literal);		# break the comment into individual lines
			foreach my $line (@commentLines)	{
				if ((($line =~ /NO GROWTH/i) and ($line !~/NO GROWTH ON ORIGINAL PLATES/i))	# if the culture was negitive increment the neg counter
				or ($line =~ /No organisms isolated anaerobically/i)
				or ($line =~ /No aerobic growth/i)){
						$negResults++;						
				}	
				elsif ((($line =~ m/^\w+.+\-\s[0-9]/) 
					or ($line =~ m/^\w+.+\-\s\s[0-9]/)
					or ($line =~ m/^\w+.+\-[0-9]/)
					or ($line =~ m/^\w+.+\-\sGREATER/)
					or ($line =~ m/^\w+.+\-\s\sGREATER/)
					or ($line =~ m/^\w+.+\-\sURINE SUBMITTED ON SWAB/)
					or ($line =~ m/-  ISOLATED FROM THIO/i)
					or ($line =~ m/- ISOLATED FROM THIO/i)
					or ($line =~ m/METHICILLIN-RESISTANT STAPH/)
					or ($line =~ m/- UNABLE TO SPECIATE/)
					or ($line =~ m/- FEW/)
					or ($line =~ m/-FEW/)
					or ($line =~ m/^Non-enteric gram negative rod/)
					or ($line =~ m/^Staphylococcus pseudintermedius/))
					and $line !~ m/Please call/i
					){
					push(@isolates, $line);								# add isolate to the isolates array
				}
			}	
		}
	}
	return (0, $totalCultures, $negResults, $source, @isolates);
}

# Parse and idenify the unit
# Return Values:
#		0: Ignore, the unit is nither a culture or a sensitivity
#		1: Unit is a culture result
#		2: Unit is a susceptibility result
sub parseUnitType {
	my $unit = $_[0];
	my($ExtID) = $unit->getAttribute("Ext-ID");							  # get the ext-id of the unit
	my($ExtValue) = $unit->findnodes('Name');							    # get the string Name of the unit
	if(my @found = grep(/\b$ExtID\b/,@cultureID)){						# check if unit is a culture
		$testCodeCounts[$ExtID]++;
		return 1;
	}
	elsif ($ExtValue->to_literal eq "SUSCEPTIBILITY"){					# if the unit is a sensitivity
		return 2;
	}	
	else{																                        # otherwise return 0 to ignore
		return 0;
	}				
}	

# SUB Parse and return the Accession Header Data
# Data Returned as hash in to_literal:
# ChartID, LabAccID, Date, Name, Age, Sex, Species, Breed, Owner, Doctor
sub parseAccessionHeader {
	my $accessionTree = $_[0];											            # passed pointer to tree
	my $header = {};													                  # array of hashes to hold header data
	my($name) = $accessionTree->findnodes('AccessionHeader/Pet/Name');
    my($age) = $accessionTree->findnodes('AccessionHeader/Pet/Age');
    my($sex) = $accessionTree->findnodes('AccessionHeader/Pet/Sex');
    my($owner) = $accessionTree->findnodes('AccessionHeader/Pet/Owner');
    my($doctor) = $accessionTree->findnodes('AccessionHeader/Pet/Doctor');
    my($species) = $accessionTree->findnodes('AccessionHeader/Pet/Species');
    my($breed) = $accessionTree->findnodes('AccessionHeader/Pet/Breed');   	
    my $chartID = "Unknown";
    my $labAccID = "Unknown";
    
    # loop through the AccessionHeader Accession-ID's and retereve chartID and Lab-AccID
    foreach my $accessionID ($accessionTree->findnodes('./AccessionHeader/Accession-ID')){
   		my($Type) = $accessionID->getAttribute("Type");
   		if($Type eq "Chart-ID"){
   			$chartID = $accessionID->getAttribute("ID");
   		}
   		elsif($Type eq "Lab-AccID"){
   			$labAccID = $accessionID->getAttribute("ID");
   		}
   }
    
    my @dateAndTime;													                    
    foreach my $timeStamps ($accessionTree->findnodes('./AccessionHeader/TimeStamp')){
    	my($timeStamp) = $timeStamps->getAttribute("Value");
    	@dateAndTime = split(" ", $timeStamp);	
    }
    
    $header = {	
    			CHARTID => $chartID, 
    			LABID => $labAccID, 
    			DATE => $dateAndTime[0],
    			NAME => $name->to_literal,
    			AGE => $age->to_literal,
    			SEX => $sex->to_literal,
    			SPECIES => $species->to_literal,
    			BREED => $breed->to_literal,
    			OWNER => $owner->to_literal,
    			DOCTOR => $doctor->to_literal
    			}; 
    return ($header);   
}

# Print the header line for the text file output
sub printHeader {
	if($printHeader == 0){
		print OUTP "LabAccNumber","\t","LabName","\t","ClinicAccNumber","\t","ClinicName","\t",
					"Chart ID","\t","Lab Acc ID","\t","Date","\t","Name","\t","Age","\t","Sex","\t","Species","\t",
					"Breed","\t","Owner","\t","Doctor","\t","Specimen","\t","Organism","\t","Growth","\t",
					"Antibiotic","\t","Result","\t","MIC","\n";
	}
}
# Print the result tab dilimited line
# Input:
#	output = (1|2) Screen (CVS), File (TVS)
#	header = hash of header data
#	isolate 
#	susceptability
sub printLine {
	my $output = $_[0];
	my $header = $_[1];
	my $source = $_[2];
	my $isolate; 
	my $growth;
	my $results;
	if($_[3]){$isolate = $_[3];}
	if ($_[4]){$growth = $_[4];}
	if($_[5]){$results = $_[5];}
	
	if ($output == 1){										# if print to screen (all results one line)
		print $labIDNumber,",",$labName,",",$clinicAccountNumber,",",$clinicName,",",$header->{CHARTID}, 
		",",$header->{LABID},",",$header->{DATE},",",$header->{NAME},",",$header->{AGE},",",$header->{SEX},
		",",$header->{SPECIES},",",$header->{BREED},",",$header->{OWNER},",",$header->{DOCTOR},",",$source;
		if ($isolate){
			print ",",$isolate,",",$growth;
		}
		if ($results){
			foreach (@{$results->{RESULTS}}){
				print ",",$_;
			}
		}
		print "\n";
	}
	elsif ($output == 0) {									# if print to file 
		if($results){
			print OUTP $labIDNumber,"\t",$labName,"\t",$clinicAccountNumber,"\t",$clinicName,"\t",$header->{CHARTID}, 
			"\t",$header->{LABID},"\t",$header->{DATE},"\t",$header->{NAME},"\t",$header->{AGE},"\t",$header->{SEX},
			"\t",$header->{SPECIES},"\t",$header->{BREED},"\t",$header->{OWNER},"\t",$header->{DOCTOR},"\t",$source;
			if ($isolate){
				print OUTP "\t",$isolate,"\t",$growth;
			}
			if ($results){
				foreach (@{$results->{RESULTS}}){
					print OUTP "\t",$_;
				}
			}
			print OUTP "\n";
		}
		elsif($isolate){
			print OUTP $labIDNumber,"\t",$labName,"\t",$clinicAccountNumber,"\t",$clinicName,"\t",
			$header->{CHARTID}, "\t",$header->{LABID},"\t",$header->{DATE},"\t",$header->{NAME},"\t",
			$header->{AGE},"\t",$header->{SEX},"\t",$header->{SPECIES},"\t",$header->{BREED},"\t",
			$header->{OWNER},"\t",$header->{DOCTOR},"\t",$source;
			print OUTP "\t",$isolate,"\t",$growth;
			print OUTP "\n";
		}
		else {
			print OUTP $labIDNumber,"\t",$labName,"\t",$clinicAccountNumber,"\t",$clinicName,"\t",
			$header->{CHARTID}, "\t",$header->{LABID},"\t",$header->{DATE},"\t",$header->{NAME},"\t",
			$header->{AGE},"\t",$header->{SEX},"\t",$header->{SPECIES},"\t",$header->{BREED},"\t",
			$header->{OWNER},"\t",$header->{DOCTOR},"\t",$source;
			print OUTP "\n";
		}
	}	
}

# prints a help screen to standard output.  Used for errors in commanline args
sub printHelp {
	if($_[0]){						# if there is a special error message
		print $_[0], "\n";
	}
	print "Idexx2Whonet v3.1 by Avi Solomon, 2010.\n",
		"Convert Idexx XML datafile to WhoNet capable txt file.",
	 	"\n\t USAGE: ",
		">idexx2whonet -s -d -En -Nh [XML filename] [TXT Filename]\n",
		"\t\t-d:  DEBUG MODE (usefull for screen printing)\n",
		"\t\t-s:  Print to Screen not file\n",
		"\t\t-En: Exclude negative results\n",	
		"\t\t-Nh: Don't print header in file [defunct] \n";
}

# Parse the clinic data from tree and return the clinic name and account
sub parseClinic {
	my $xmlRef = $_[0];
	foreach my $clinic ($xmlRef->findnodes('/LabReport/Clinic')) {
		my($accountNumber) = $clinic->getAttribute("AccountNumber");
		my($clinicName) = $clinic->findnodes('Name');
		return ($accountNumber, $clinicName->to_literal);
	}
}

# Parse the lab data from tree and return the labID and LabName
sub parseLab {
	my $xmlRef = $_[0];
	foreach my $lab ($xmlRef->findnodes('/LabReport/LabLocation')) {
		my($labID) = $lab->getAttribute("LabId");
		my($labName) = $lab->findnodes('LocationName');
		return ($labID, $labName->to_literal);
	}
}


