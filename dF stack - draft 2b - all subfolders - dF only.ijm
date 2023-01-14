file_suffix = "_?[0-9]*\\.ome-?[0-9]*.tif$"; //Regex pattern for file suffixes
noise_z_median = 5; //Denoise the raw movie
bkgnd_subsample = 5; //Size of subsample interval to speed up bkgnd median
bkgnd_z_median = 20; //Size of time median filter to remove waves for dF stack
blur = 5; //Gaussian blur to solidify waves and smooth individual cell details
threshold = 1.02; //dF threshold for retinal wave
max_image_width = 800; //Cap the size of the images to be processed, filter out unbinned images, etc.
min_image_width = 100; //Exclude images too small to determine wave propagation.
analyze_subdir = false;

close("*");
setBatchMode(true);
run("Bio-Formats Macro Extensions"); //Get metadata without opening entire file

dir = getDirectory("Choose the root directory to process");
out_dir = dir + "Processed Images/";
count = 0;
countFiles(dir, out_dir);
n = 0;
processFiles(dir, out_dir);

function countFiles(dir, out_dir) {
  list = getFileList(dir);
  File.makeDirectory(out_dir);
  for (i=0; i<list.length; i++) {
      if (endsWith(list[i], "/"))
      	countFiles(""+dir+list[i], ""+out_dir+list[i]);
      else if(matches(list[i], ".*" + file_suffix) && analyze_subdir){
  		count++;
      } 	
  }
}

function processFiles(dir, out_dir) {
  file_list = getFileList(dir);
  for (i=0; i<file_list.length; i++) {
      if(endsWith(file_list[i], "/") && analyze_subdir)
          processFiles(""+dir+file_list[i], ""+out_dir+file_list[i]);
      else if(matches(file_list[i], ".*" + file_suffix)){
      	close("*");
      	run("Collect Garbage");
      	file_prefix = replace(file_list[i], file_suffix, "");
      	Ext.setId(dir+file_list[i]);
      	Ext.getSizeX(sizeX);
      	Ext.close();
		if(sizeX >= min_image_width && sizeX <= max_image_width){
	      	//Open full length movie as one stack
	      	print("---------------------------------------");
	      	print(dir);
	      	printUpdate("Prefix: " + file_prefix);
			for(a=i; a<file_list.length; a++){
				if(startsWith(file_list[a], file_prefix) && matches(file_list[a], ".*" + file_suffix)){
					open(dir + file_list[a]);
					n++;
				}
				else break;
			}
			printUpdate("File opened: " + a-i);
			i=a;
			if(nImages > 1) run("Concatenate...", "all_open title=stack");
			else if(nImages < 1);
			else rename("stack");
			showProgress(n, count);
			processFile(file_prefix, out_dir);    
	      }
	      else{
	      	print("Skipped - wrong width: " + dir + file_list[i] + " width = " + sizeX);
	      }
      }
  }
}

function processFile(file_prefix, out_dir) {
	dFstack();
	selectWindow("dF");
	saveAs("tiff", out_dir + "dF stack - " + file_prefix + ".tif");
	printUpdate("dF stack saved");
	run("Close All");
	close("*");
	wait(5000);
	run("Collect Garbage"); //https://imagejdocu.list.lu/faq/technical/how_do_i_run_the_garbage_collector_in_a_macro_or_plugin
	return;
	
	segmentWaves();
	selectWindow("watershed");
	close("\\Others");
	wait(5000);
	run("Collect Garbage");
	saveAs("tiff", out_dir + "watershed - " + file_prefix + ".tif");
	rename("watershed");
	printUpdate("watershed saved");
	createHistogram();
	selectWindow("Histogram");
	close("\\Others");
	wait(5000);
	run("Collect Garbage");
	saveAs("tiff", out_dir + "histogram - " + file_prefix + ".tif");
	close("*");
	printUpdate("histogram saved");
	setBatchMode("exit and display");
	exit();
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
function segmentWaves(){
	selectWindow("dF");
	run("Gaussian Blur...", "sigma=" + blur + " stack");
	run("Duplicate...", "title=mask duplicate");
	selectWindow("mask");
	setThreshold(threshold, 1e30);
	run("Convert to Mask", "method=Yen background=Dark black");
	run("Invert", "stack");
	run("Classic Watershed", "input=mask mask=None use min=0 max=1");
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

