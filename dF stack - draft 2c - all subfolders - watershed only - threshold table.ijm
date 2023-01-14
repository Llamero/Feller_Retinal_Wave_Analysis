file_suffix = "_?[0-9]*\\.ome-?[0-9]*.tif$"; //Regex pattern for file suffixes
noise_z_median = 5; //Denoise the raw movie
bkgnd_subsample = 5; //Size of subsample interval to speed up bkgnd median
bkgnd_z_median = 20; //Size of time median filter to remove waves for dF stack
blur = 5; //Gaussian blur to solidify waves and smooth individual cell details
threshold = 1.02; //dF threshold for retinal wave
max_image_width = 800; //Cap the size of the images to be processed, filter out unbinned images, etc.
min_image_width = 100; //Exclude images too small to determine wave propagation.

close("*");
setBatchMode(true);
if(!isOpen("Thresholds")){
	threshold_file = File.openDialog("Select the thresholds table");
	open(threshold_file);
	threshold_file = File.getName(threshold_file);
	Table.rename(threshold_file, "Thresholds");
}
dir = getDirectory("Choose the root directory to process");
//out_dir = dir + "Processed Images/";
out_dir = dir;
count = 0;
countFiles(dir, out_dir);
print(count);
n = 0;
processFiles(dir, out_dir);

function countFiles(dir, out_dir) {
  list = getFileList(dir);
//  File.makeDirectory(out_dir);
  for (i=0; i<list.length; i++) {
      if (endsWith(list[i], "/"))
      	countFiles(""+dir+list[i], ""+out_dir+list[i]);
      else if(startsWith(list[i], "dF stack - ")){
  		count++;
      } 	
  }
}

function processFiles(dir, out_dir) {
  file_list = getFileList(dir);
  for (i=0; i<file_list.length; i++) {
      if(endsWith(file_list[i], "/"))
          processFiles(""+dir+file_list[i], ""+out_dir+file_list[i]);
      else if(startsWith(file_list[i], "dF stack - ") && endsWith(file_list[i], "tif")){
      	close("*");
      	run("Collect Garbage");
      	//Open full length movie as one stack
      	print("---------------------------------------");
      	print(dir);
      	file_prefix = replace(file_list[i], "dF stack - ", "");
      	file_prefix = replace(file_prefix, ".tif$", "");
      	printUpdate("Prefix: " + file_prefix);
		open(dir + file_list[i]);
		rename("dF");
		showProgress(n, count);
		processFile(file_prefix, out_dir);
      }        
  }
}

function processFile(file_prefix, out_dir) {
	segmentWaves(file_prefix, out_dir);
	selectWindow("watershed");
	close("\\Others");
	saveAs("tiff", out_dir + "watershed - " + file_prefix + ".tif");
	rename("watershed");
	printUpdate("watershed saved");
	close("*");
	wait(5000);
	run("Collect Garbage");
}

//Create dF stack
function dFstack(){
	selectWindow("stack");
	Stack.getDimensions(width, height, channels, slices, frames);
	run("Slice Keeper", "first=1 last=" + slices + " increment=" + bkgnd_subsample);
	selectWindow("stack kept stack");
	run("Median 3D...", "x=0 y=0 z=" + bkgnd_z_median);
	run("Size...", "width=" + width + " height=" + height + " depth=" + slices + " constrain average interpolation=Bilinear");
	selectWindow("stack");
	run("Median 3D...", "x=0 y=0 z=" + noise_z_median);
	imageCalculator("Divide create 32-bit stack", "stack","stack kept stack");
	close("stack");
	close("stack kept stack");
	selectWindow("Result of stack");
	rename("dF");
}

//Segment waves
function segmentWaves(file_prefix, out_dir){
	selectWindow("Thresholds");
	for(a=0; a<=Table.size; a++){
		folder = Table.getString("experiment", a);
		file = Table.getString("filename", a);
		file_prefix_fix = replace(file_prefix, "220511_", "");
		if(matches(out_dir, ".*/" + folder + "/.*") && matches(file, ".*" + file_prefix_fix + ".*")){
			threshold = Table.get("threshold", a);
			print(threshold);
			break;
		}
	}
	if(a>=Table.size) showMessage("ERROR: THRESHOLD NOT FOUND FOR: " + file_prefix);
	selectWindow("dF");
	run("Gaussian Blur...", "sigma=" + blur + " stack");
	printUpdate("Segment - blur complete");
	rename("mask");
	selectWindow("mask");
	setThreshold(threshold, 1e30);
	run("Convert to Mask", "method=Yen background=Dark black");
	run("Invert", "stack");
	printUpdate("Segment - mask complete");
	run("Classic Watershed", "input=mask mask=None use min=0 max=1");
	printUpdate("Segment - watershed complete");
}

//Create histogram of waves
function createHistogram(){
	selectWindow("watershed");
	Stack.getStatistics(dummy, dummy, dummy, max, dummy);
	Stack.getDimensions(dummy, dummy,dummy, slices, dummy);
	newImage("Histogram", "32-bit black", max+1, slices, 1);
	for(a=1; a<=slices; a++){
		selectWindow("watershed");
		Stack.setSlice(a);
		getHistogram(values, counts, max, 0, max);
		selectWindow("Histogram");
		for(b=0; b<counts.length; b++){
			setPixel(b, a-1, counts[b]);
		}
	}
}

//Color waves by volume
function colorWaveVolume(){
	selectWindow("Histogram");
	run("Duplicate...", "title=[stack histogram]");
	selectWindow("stack histogram");
	getDimensions(width, height, dummy, dummy, dummy);
	run("Bin...", "x=1 y=" + height + " bin=Sum");
	for(y=0; y<height; y++){
		print(y + " of " + height);
		macro_string = "code=[";
		for(x=1; x<width; x++){
			selectWindow("Histogram");
			value = getPixel(x,y);
			if(value > 0){
				selectWindow("stack histogram");
				count = getPixel(x, 0);
				macro_string = macro_string + "if(v==" + x + ") v=" + count + "; ";
			}
		}
		macro_string = macro_string + "] slice";
		selectWindow("watershed");
		Stack.setSlice(y+1);
		if(!matches(macro_string, "code=\\[\\] slice")){
			run("Macro...", macro_string);
		}
		showProgress(y, height);
	}
}

function printUpdate(message){ //https://imagej.nih.gov/ij/macros/GetDateAndTime.txt
	MonthNames = newArray("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
	DayNames = newArray("Sun", "Mon","Tue","Wed","Thu","Fri","Sat");
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	TimeString ="Date: "+DayNames[dayOfWeek]+" ";
	if (dayOfMonth<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+dayOfMonth+"-"+MonthNames[month]+"-"+year+"\nTime: ";
	if (hour<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+hour+":";
	if (minute<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+minute+":";
	if (second<10) {TimeString = TimeString+"0";}
	TimeString = TimeString+second;
	print(TimeString +  " - " + message);
}

setBatchMode("exit and display");

