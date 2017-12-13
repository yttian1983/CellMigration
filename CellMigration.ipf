#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#pragma version=1.07		// version number of Migrate()
#include <Waves Average>

// LoadMigration contains 3 procedures to analyse cell migration in IgorPro
// Use ImageJ to track the cells. Outputs from tracking are saved in sheets in an Excel Workbook, 1 per condition
// Execute Migrate().
// This function will trigger the load and the analysis of cell migration via two functions
// LoadMigration() - will load all sheets of migration data from a specified excel file
// MakeTracks() - does the analysis
// NOTE no headers in Excel file. Keep data to columns A-H, max of 2000 rows
// columns are
// A - 0 - ImageJ row
// B - 1 - Track No
// C - 2 - Slice No
// D - 3 - x (in px)
// E - 4 - y (in px)
// F - 5 - distance
// G - 6 - speed
// H - 7 - pixel value

// Menu item for easy execution
Menu "Macros"
	"Cell Migration...",  SetUpMigration()
End

Function SetUpMigration()
	SetDataFolder root:
	// kill all windows and waves before we start
	CleanSlate()
	
	Variable cond = 2
	Variable tStep = 20
	Variable pxSize = 0.22698
	
	Prompt cond, "How many conditions?"
	Prompt tStep, "Time interval (min)"
	Prompt  pxSize, "Pixel size (�m)"
	DoPrompt "Specify", cond, tStep, pxSize
	
	Make/O/N=3 paramWave={cond,tStep,pxSize}
	MakeColorWave(cond)
	myIO_Panel(cond)
End

// Loads the data and performs migration analysis
Function Migrate()
	WAVE/Z paramWave = root:paramWave
	if(!WaveExists(paramWave))
		Abort "Setup has failed. Missing paramWave."
	endif
	
	Variable cond = paramWave[0]
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	
	WAVE/Z colorWave = root:colorWave
	Make/O/T/N=(cond) sum_Label
	Make/O/N=(cond) sum_MeanSpeed, sum_SemSpeed, sum_NSpeed
	Make/O/N=(cond) sum_MeanIV, sum_SemIV
	
	String pref, lab
	
	String fullList = "cdPlot;ivPlot;ivHPlot;dDPlot;MSDPlot;DAPlot;"
	String name
	Variable i
	
	for(i = 0; i < 6; i += 1)
		name = StringFromList(i, fullList)
		KillWindow/Z $name
		Display/N=$name/HIDE=1		
	endfor
	
	String dataFolderName = "root:data"
	NewDataFolder/O $dataFolderName // make root:data: but don't put anything in it yet
	
	WAVE/T condWave = root:condWave
	Variable moviemax1, moviemax2
	
	for(i = 0; i < cond; i += 1)
		pref = condWave[i]
		
		// add underscore if user forgets
		if(StringMatch(pref,"*_") == 0)
			pref = pref + "_"
		endif
		// make label wave from graphs (underscore-less)
		lab = ReplaceString("_",pref,"")
		sum_Label[i] = lab
		
		// make data folder
		dataFolderName = "root:data:" + RemoveEnding(pref)
		NewDataFolder/O/S $dataFolderName
		// run other procedures
		moviemax1 = LoadMigration(pref,i)
		moviemax2 = CorrectMigration(pref,i)
		if(moviemax1 != moviemax2)
			if(moviemax2 == -1)
				print "No correction applied to", RemoveEnding(pref)
			else
				print "Caution: different number of stationary tracks compared with real tracks."
			endif
		endif
		// for each condition go and make tracks and plot everything out
		MakeTracks(pref,i)
		SetDataFolder root:
	endfor
	
	KillWindow/Z summaryLayout
	NewLayout/N=summaryLayout
	
	// Tidy up summary windows
	SetAxis/W=cdPlot/A/N=1 left
	Label/W=cdPlot left "Cumulative distance (�m)"
	Label/W=cdPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph cdPlot
	SetAxis/W=ivPlot/A/N=1 left
	Label/W=ivPlot left "Instantaneous Speed (�m/min)"
	Label/W=ivPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph ivPlot
	SetAxis/W=ivHPlot/A/N=1 left
	SetAxis/W=ivHPlot bottom 0,2
	Label/W=ivHPlot left "Frequency"
	Label/W=ivHPlot bottom "Instantaneous Speed (�m/min)"
	ModifyGraph/W=ivHPlot mode=6
		AppendLayoutObject /W=summaryLayout graph ivHPlot
	Label/W=dDPlot left "Directionality ratio (d/D)"
	Label/W=dDPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph dDPlot
	ModifyGraph/W=MSDPlot log=1
	SetAxis/W=MSDPlot/A/N=1 left
	Wave w = WaveRefIndexed("MSDPlot",0,1)
	SetAxis/W=MSDPlot bottom tStep,((numpnts(w) * tStep)/2)
	Label/W=MSDPlot left "MSD"
	Label/W=MSDPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph MSDPlot
	SetAxis/W=DAPlot left 0,1
	Wave w = WaveRefIndexed("DAPlot",0,1)
	SetAxis/W=DAPlot bottom 0,((numpnts(w)*tStep)/2)
	Label/W=DAPlot left "Direction autocorrelation"
	Label/W=DAPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph DAPlot
	
	// average the speed data from all conditions	
	String wList, newName, wName
	Variable nTracks, last, j
	
	for(i = 0; i < cond; i += 1)
		pref = sum_Label[i] + "_"
		dataFolderName = "root:data:" + RemoveEnding(pref)
		SetDataFolder $dataFolderName
		wList = WaveList("cd_" + pref + "*", ";","")
		nTracks = ItemsInList(wList)
		newName = "sum_Speed_" + RemoveEnding(pref)
		Make/O/N=(nTracks) $newName
		WAVE w0 = $newName
		for(j = 0; j < nTracks; j += 1)
			wName = StringFromList(j,wList)
			Wave w1 = $wName
			last = numpnts(w1) - 1	// finds last row (max cumulative distance)
			w0[j] = w1[last]/(last*tStep)	// calculates speed
		endfor
		WaveStats/Q w0
		sum_MeanSpeed[i] = V_avg
		sum_SemSpeed[i] = V_sem
		sum_NSpeed[i] = V_npnts
	endfor
	KillWindow/Z SpeedTable
	Edit/N=SpeedTable/HIDE=1 sum_Label,sum_MeanSpeed,sum_MeanSpeed,sum_SemSpeed,sum_NSpeed
	KillWindow/Z SpeedPlot
	Display/N=SpeedPlot/HIDE=1 sum_MeanSpeed vs sum_Label
	Label/W=SpeedPlot left "Speed (�m/min)"
	SetAxis/W=SpeedPlot/A/N=1/E=1 left
	ErrorBars/W=SpeedPlot sum_MeanSpeed Y,wave=(sum_SemSpeed,sum_SemSpeed)
	ModifyGraph/W=SpeedPlot zColor(sum_MeanSpeed)={colorwave,*,*,directRGB,0}
	ModifyGraph/W=SpeedPlot hbFill=2
	AppendToGraph/R/W=SpeedPlot sum_MeanSpeed vs sum_Label
	SetAxis/W=SpeedPlot/A/N=1/E=1 right
	ModifyGraph/W=SpeedPlot hbFill(sum_MeanSpeed#1)=0,rgb(sum_MeanSpeed#1)=(0,0,0)
	ModifyGraph/W=SpeedPlot noLabel(right)=2,axThick(right)=0,standoff(right)=0
	ErrorBars/W=SpeedPlot sum_MeanSpeed#1 Y,wave=(sum_SemSpeed,sum_SemSpeed)
		AppendLayoutObject /W=summaryLayout graph SpeedPlot
	
	// average instantaneous speed variances
	for(i = 0; i < cond; i += 1) // loop through conditions, 0-based
		pref = sum_Label[i] + "_"
		dataFolderName = "root:data:" + RemoveEnding(pref)
		SetDataFolder $dataFolderName
		wList = WaveList("iv_" + pref + "*", ";","")
		nTracks = ItemsInList(wList)
		newName = "sum_ivVar_" + ReplaceString("_",pref,"")
		Make/O/N=(nTracks) $newName
		WAVE w0 = $newName
		for(j = 0; j < nTracks; j += 1)
			wName = StringFromList(j,wList)
			Wave w1 = $wName
			w0[j] = variance(w1)	// calculate varance for each cell
		endfor
		WaveStats/Q w0
		sum_MeanIV[i] = V_avg
		sum_SemIV[i] = V_sem
	endfor
	AppendToTable/W=SpeedTable sum_MeanIV,sum_SemIV
	KillWindow/Z IVCatPlot
	Display/N=IVCatPlot/HIDE=1 sum_MeanIV vs sum_Label
	Label/W=IVCatPlot left "Variance (�m/min)"
	SetAxis/W=IVCatPlot/A/N=1/E=1 left
	ErrorBars/W=IVCatPlot sum_MeanIV Y,wave=(sum_SemIV,sum_SemIV)
	ModifyGraph/W=IVCatPlot zColor(sum_MeanIV)={colorwave,*,*,directRGB,0}
	ModifyGraph/W=IVCatPlot hbFill=2
	AppendToGraph/R/W=IVCatPlot sum_MeanIV vs sum_Label
	SetAxis/W=IVCatPlot/A/N=1/E=1 right
	ModifyGraph/W=IVCatPlot hbFill(sum_MeanIV#1)=0,rgb(sum_MeanIV#1)=(0,0,0)
	ModifyGraph/W=IVCatPlot noLabel(right)=2,axThick(right)=0,standoff(right)=0
	ErrorBars/W=IVCatPlot sum_MeanIV#1 Y,wave=(sum_SemIV,sum_SemIV)
		AppendLayoutObject /W=summaryLayout graph IVCatPlot
	
	SetDataFolder root:
	
	// Tidy summary layout
	DoWindow/F summaryLayout
	// in case these are not captured as prefs
	LayoutPageAction size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
	ModifyLayout units=0
	ModifyLayout frame=0,trans=1
	Execute /Q "Tile"

	// when we get to the end, print (pragma) version number
	Print "*** Executed Migrate v", GetProcedureVersion("CellMigration.ipf")
	KillWindow/Z FilePicker
End

// This function will load the tracking data
/// @param pref	prefix for condition
/// @param	ii	variable containing row number from condWave
Function LoadMigration(pref,ii)
	String pref
	Variable ii
	
	WAVE/T PathWave1 = root:PathWave1
	String pathString = PathWave1[ii]
	String sheet, prefix, matName, wList
	String fileList
	Variable moviemax,csvOrNot
	Variable i
	
	if(StringMatch(pathString, "*.xls*") == 1)
		// set variable to indicate Excel Workbook
		csvOrNot = 0
		// Works out what sheets are in Excel Workbook and then loads each.
		XLLoadWave/J=1 PathWave1[ii]
		fileList = S_value
	else
		// set variable to indicate csv file
		csvOrNot = 1
		// Work out what files are in directory
		NewPath/O/Q ExpDiskFolder, pathString
		fileList = IndexedFile(expDiskFolder,-1,".csv")
	endif
	fileList = SortList(fileList, ";", 16)
	moviemax = ItemsInList(fileList)
		
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i, fileList)
		prefix = pref + "c_" + num2str(i)
		matName = pref + num2str(i)
		if(csvOrNot == 0)
			XLLoadWave/S=sheet/R=(A1,H2000)/O/K=0/N=$prefix/Q PathWave1[ii]
		else
			LoadWave/A=$prefix/J/K=1/L={0,1,0,0,0}/O/P=expDiskFolder/Q sheet
		endif
		wList = wavelist(prefix + "*",";","")	// make matrix for each sheet
		Concatenate/O/KILL wList, $matName
		// check that distances and speeds are correct
		Wave matTrax = $matName
		// make sure 1st point is -1
		matTrax[0][5,6] = -1
		CheckDistancesAndSpeeds(matTrax)
	endfor	
		
	Print "*** Condition", RemoveEnding(pref), "was loaded from", pathString
	
	// return moviemax back to calling function for checking
	return moviemax
End

// The purpose of this function is to work out whether the distances (and speeds) in the
// original data are correct. Currently it just corrects them rather than testing and correcting if needed.
Function CheckDistancesAndSpeeds(matTrax)
	WAVE matTrax
	
	WAVE/Z paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	
	// make new distance column
	Duplicate/O/RMD=[][3,4]/FREE matTrax,tempDist // take offset coords
	Differentiate/METH=2 tempDist
	tempDist[][] = (matTrax[p][5] == -1) ? 0 : tempDist[p][q]
	MatrixOp/O/FREE tempNorm = sqrt(sumRows(tempDist * tempDist))
	tempNorm[] *= pxSize // convert to real distance
	MatrixOp/O/FREE tempReal = sumcols(tempNorm - col(matTrax,5))
	matTrax[][5] = (matTrax[p][5] == -1) ? -1 : tempNorm[p] // going to leave first point as -1
	// correct speed column
	matTrax[][6] = (matTrax[p][6] == -1) ? -1 : tempNorm[p] / tStep
	// make sure 1st point is -1
	matTrax[0][5,6] = -1
End

// This function will load the tracking data from an Excel Workbook
///	@param	pref	prefix for excel workbook e.g. "ctrl_"
///	@param	ii	variable containing row number from condWave
Function CorrectMigration(pref,ii)
	String pref
	Variable ii
	
	WAVE/T PathWave2 = root:PathWave2
	String pathString = PathWave2[ii]
	Variable len = strlen(pathString)
	if(len == 0)
		return -1
	elseif(numtype(len) == 2)
		return -1
	endif
	
	String sheet, prefix, matName, wList, mName
	String fileList
	Variable moviemax,csvOrNot
	Variable i
	
	if(StringMatch(pathString, "*.xls*") == 1)
		// set variable to indicate Excel Workbook
		csvOrNot = 0
		// Works out what sheets are in Excel Workbook and then loads each.
		XLLoadWave/J=1 PathWave2[ii]
		fileList = S_value
	else
		// set variable to indicate csv file
		csvOrNot = 1
		// Work out what files are in directory
		NewPath/O/Q ExpDiskFolder, pathString
		fileList = IndexedFile(expDiskFolder,-1,".csv")
	endif
	fileList = SortList(fileList, ";", 16)
	moviemax = ItemsInList(fileList)
		
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i,fileList)
		prefix = "stat_" + "c_" + num2str(i)	// use stat prefix
		matName = "stat_" + num2str(i)
		if(csvOrNot == 0)
			XLLoadWave/S=sheet/R=(A1,H2000)/O/K=0/N=$prefix/Q PathWave2[ii]
		else
			LoadWave/A=$prefix/J/K=1/L={0,1,0,0,0}/O/P=expDiskFolder/Q sheet
		endif
		wList = wavelist(prefix + "*",";","")	// make matrix for each sheet
		Concatenate/O/KILL wList, $matName
		Wave matStat = $matName
		// Find corresponding movie matrix
		mName = ReplaceString("stat_",matname,pref)
		Wave matTrax = $mName
		OffsetAndRecalc(matStat,matTrax)
	endfor
	
	Print "*** Offset data for ondition", RemoveEnding(pref), "was loaded from", pathString

	// return moviemax back to calling function for checking
	return moviemax
End

// This function uses matStat to offset matTrax
Function OffsetAndRecalc(matStat,matTrax)
	Wave matStat,matTrax
	// Work out offset for the stat_* waves
	Variable x0 = matStat[0][3]
	Variable y0 = matStat[0][4]
	matStat[][3] -= x0
	matStat[][4] -= y0
	MatrixOp/O/FREE mStat2 = col(matStat,2)
	Variable maxFrame = WaveMax(mStat2)
	Variable j // because i refers to rows
	
	// offsetting loop
	for(j = 1; j < maxFrame + 1; j += 1)
		FindValue/V=(j) mStat2
		if(V_Value == -1)
			x0 = 0
			y0 = 0
		else
			x0 = matStat[V_Value][3]
			y0 = matStat[V_Value][4]
		endif
		matTrax[][3] = (matTrax[p][2] == j) ? matTrax[p][3] - x0 : matTrax[p][3]
		matTrax[][4] = (matTrax[p][2] == j) ? matTrax[p][4] - y0 : matTrax[p][4]
	endfor
	WAVE/Z paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	// make new distance column
	Duplicate/O/RMD=[][3,4]/FREE matTrax,tempDist // take offset coords
	Differentiate/METH=2 tempDist
	tempDist[][] = (matTrax[p][5] == -1) ? 0 : tempDist[p][q]
	MatrixOp/O/FREE tempNorm = sqrt(sumRows(tempDist * tempDist))
	tempNorm[] *= pxSize // convert to real distance
	matTrax[][5] = (matTrax[p][5] == -1) ? -1 : tempNorm[p] // going to leave first point as -1
	// correct speed column
	matTrax[][6] = (matTrax[p][6] == -1) ? -1 : tempNorm[p] / tStep
	// put 1st point as -1
	matTrax[0][5,6] = -1
End

// This function will make cumulative distance waves for each cell. They are called cd_*
/// @param pref	prefix for excel workbook e.g. "ctrl_"
/// @param tStep	timestep. Interval/frame rate of movie.
/// @param pxSize	pixel size. xy scaling.
Function MakeTracks(pref,ii)
	String pref
	Variable ii
	
	WAVE/Z paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	WAVE/Z colorWave = root:colorWave
	
	String wList0 = WaveList(pref + "*",";","") // find all matrices
	Variable nWaves = ItemsInList(wList0)
	
	Variable nTrack
	String mName0, newName, plotName, avList, avName, errName
	Variable i, j
	
	String layoutName = pref + "layout"
	KillWindow/Z $layoutName		// Kill the layout if it exists
	NewLayout/HIDE=1/N=$layoutName	

	// cumulative distance and plot over time	
	plotName = pref + "cdplot"
	KillWindow/Z $plotName	// set up plot
	Display/N=$plotName/HIDE=1

	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][5,5] m0, tDistW	// distance
		Duplicate/O/RMD=[][1,1] m0, tCellW	// cell number
		Redimension/N=-1 tDistW, tCellW // make 1D
		nTrack = WaveMax(tCellW)	// find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	// index is 1-based
			newName = "cd_" + mName0 + "_" + num2str(j)
			Duplicate/O tDistW $newName
			WAVE w2 = $newName
			w2 = (tCellW[p] == j) ? tDistW[p] : NaN
			WaveTransform zapnans w2
			if(numpnts(w2) <= (ceil(60/tstep)))
				KillWaves/Z w2	// get short tracks and any tracks that didn't exist
			else
				w2[0] = 0	// first point in distance trace is -1 so correct this
				Integrate/METH=0 w2	// make cumulative distance
				SetScale/P x 0,tStep,"min", w2
				AppendtoGraph/W=$plotName $newName
			endif
		endfor
		KillWaves/Z tDistW
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],32767)
	avList = Wavelist("cd*",";","WIN:"+ plotName)
	avName = "W_Ave_cd_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, AvName, ErrName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Cumulative distance (�m)"
	ErrorBars/W=$plotName $avName Y,wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// instantaneous speed over time	
	plotName = pref + "ivplot"
	KillWindow/Z $plotName	// set up plot
	Display/N=$plotName/HIDE=1

	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][5,5] m0, tDistW	// distance
		Duplicate/O/RMD=[][1,1] m0, tCellW	// cell number
		Redimension/N=-1 tDistW, tCellW // make 1D
		nTrack = WaveMax(tCellW)	// find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	// index is 1-based
			newName = "iv_" + mName0 + "_" + num2str(j)
			Duplicate/O tDistW $newName
			WAVE w2 = $newName
			w2 = (tCellW[p] == j) ? tDistW[p] : NaN
			WaveTransform zapnans w2
			if(numpnts(w2) <= (ceil(60/tstep)))
				KillWaves w2
			else
				w2[0] = 0	// first point in distance trace is -1, so correct this
				w2 /= tStep	// make instantaneous speed (units are �m/min)
				SetScale/P x 0,tStep,"min", w2
				AppendtoGraph/W=$plotName $newName
			endif
		endfor
		KillWaves/Z tDistW
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],32767)
	avList = Wavelist("iv*",";","WIN:"+ plotName)
	avName = "W_Ave_iv_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, AvName, ErrName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Instantaneous Speed (�m/min)"
	ErrorBars/W=$plotName $avName Y,wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	plotName = pref + "ivHist"
	KillWindow/Z $plotName	//set up plot
	Display/N=$plotName/HIDE=1
	
	Concatenate/O/NP avList, tempwave
	newName = pref + "ivHist"	// note that this makes a name like Ctrl_ivHist
	Variable bval=ceil(wavemax(tempwave)/(sqrt((3*pxsize)^2)/tStep))
	Make/O/N=(bval) $newName
	Histogram/P/B={0,(sqrt((3*pxsize)^2)/tStep),bVal} tempwave,$newName
	AppendToGraph/W=$plotName $newName
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	ModifyGraph/W=$plotName mode=5,hbFill=4
	SetAxis/W=$plotName/A/N=1/E=1 left
	SetAxis/W=$plotName bottom 0,2
	Label/W=$plotName left "Frequency"
	Label/W=$plotName bottom "Instantaneous Speed (�m/min)"
	KillWaves/Z tempwave
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// plot out tracks
	plotName = pref + "tkplot"
	KillWindow/Z $plotName	//set up plot
	Display/N=$plotName/HIDE=1
	
	Variable off
	
	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][3,3] m0, tXW	//x pos
		Duplicate/O/RMD=[][4,4] m0, tYW	//y pos
		Duplicate/O/RMD=[][1,1] m0, tCellW	//track number
		Redimension/N=-1 tXW,tYW,tCellW		
		nTrack = WaveMax(tCellW)	//find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	//index is 1-based
			newName = "tk_" + mName0 + "_" + num2str(j)
			Duplicate/O tXW, w3	// tried to keep wn as references, but these are very local
			w3 = (tCellW[p] == j) ? w3[p] : NaN
			WaveTransform zapnans w3
			if(numpnts(w3) <= (ceil(60/tstep)))
				KillWaves w3
			else
				off = w3[0]
				w3 -= off	//set to origin
				w3 *= pxSize
				// do the y wave
				Duplicate/O tYW, w4
				w4 = (tCellW[p] == j) ? w4[p] : NaN
				WaveTransform zapnans w4
				off = w4[0]
				w4 -= off
				w4 *= pxSize
				Concatenate/O/KILL {w3,w4}, $newName
				WAVE w5 = $newName
				AppendtoGraph/W=$plotName w5[][1] vs w5[][0]
			endif
		endfor
		Killwaves/Z tXW,tYW,tCellW //tidy up
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],32767)
	SetAxis/W=$plotName left -250,250
	SetAxis/W=$plotName bottom -250,250
	ModifyGraph/W=$plotName width={Plan,1,bottom,left}
	ModifyGraph/W=$plotName mirror=1
	ModifyGraph/W=$plotName grid=1
	ModifyGraph/W=$plotName gridRGB=(32767,32767,32767)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate d/D directionality ratio
	plotName = pref + "dDplot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	
	String wName0, wName1
	Variable len
	wList0 = WaveList("tk_" + pref + "*", ";","")
	nWaves = ItemsInList(wList0)
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)			// tk wave
		wName1 = ReplaceString("tk",wName0,"cd")	// cd wave
		WAVE w0 = $wName0
		WAVE w1 = $wName1
		newName = ReplaceString("tk",wName0,"dD")
		Duplicate/O w1 $newName
		WAVE w2 = $newName
		len = numpnts(w2)
		w2[] = (w1[p] == 0) ? 1 : sqrt(w0[p][0]^2 + w0[p][1]^2) / w1[p]
		w2[0] = NaN	// d/D at point 0 is not a number
		AppendtoGraph/W=$plotName w2
	Endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],32767)
	avList = Wavelist("dD*",";","WIN:"+ plotName)
	avName = "W_Ave_dD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, AvName, ErrName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Directionality ratio (d/D)"
	Label/W=$plotName bottom "Time (min)"
	ErrorBars/W=$plotName $avName Y,wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate MSD (overlapping method)
	plotName = pref + "MSDplot"
	KillWindow/Z $plotName	//setup plot
	Display/N=$plotName/HIDE=1
	
	wList0 = WaveList("tk_" + pref + "*", ";","")
	nWaves = ItemsInList(wList0)
	Variable k
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)	// tk wave
		WAVE w0 = $wName0
		len = DimSize(w0,0)
		newName = ReplaceString("tk",wName0,"MSD")	// for results of MSD per cell
		Make/O/N=(len-1,len-1,2)/FREE tempMat0,tempMat1
		// make 2 3D waves. 0 is end point to measure MSD, 1 is start point
		// layers are x and y
		tempMat0[][][] = (p >= q) ? w0[p+1][r] : 0
		tempMat1[][][] = (p >= q) ? w0[p-q][r] : 0
		MatrixOp/O/FREE tempMat2 = (tempMat0 - tempMat1) * (tempMat0 - tempMat1))
		Make/O/N=(len-1)/FREE countOfMSDPnts = (len-1)-p
		MatrixOp/O $newName = sumcols(sumbeams(tempMat2))^t / countOfMSDPnts
		SetScale/P x 0,tStep,"min", $newName
		AppendtoGraph/W=$plotName $newName
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],32767)
	avList = Wavelist("MSD*",";","WIN:"+ plotName)
	avName = "W_Ave_MSD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	ModifyGraph/W=$plotName log=1
	SetAxis/W=$plotName/A/N=1 left
	len = numpnts($avName)*tStep
	SetAxis/W=$plotName bottom tStep,(len/2)
	Label/W=$plotName left "MSD"
	Label/W=$plotName bottom "Time (min)"
	ErrorBars/W=$plotName $avName Y,wave=($errName,$errName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject /W=$layoutName graph $plotName
	
	// calculate direction autocorrelation
	plotName = pref + "DAplot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)			// tk wave
		WAVE w0 = $wName0
		len = DimSize(w0,0)	// len is number of frames
		Differentiate/METH=2/DIM=0/EP=1 w0 /D=vWave // make vector wave. nVectors is len-1
		MatrixOp/O/FREE magWave = sqrt(sumrows(vWave * vWave))
		vWave[][] /= magWave[p]	// normalise vectors
		newName = ReplaceString("tk",wName0,"DA")	// for results of DA per cell
		Make/O/N=(len-2,len-2,2)/FREE tempDAMat0,tempDAMat1
		tempDAMat0[][][] = (p >= q) ? vWave[p-q][r] : 0
		tempDAMat1[][][] = (p >= q) ? vWave[p+1][r] : 0
		MatrixOp/O/FREE dotWave = (tempDAMat0 * tempDAMat1)
		MatrixOp/O/FREE alphaWave = sumBeams(dotWave)
		// Make average
		Make/O/N=(len-2)/FREE countOfDAPnts = (len-2)-p
		MatrixOp/O $newName = sumcols(alphaWave)^t / countOfDAPnts
		SetScale/P x 0,tStep,"min", $newName
		AppendtoGraph/W=$plotName $newName
	endfor
	Killwaves/Z vWave
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],32767)
	avList = Wavelist("DA*",";","WIN:"+ plotName)
	avName = "W_Ave_DA_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	SetAxis/W=$plotName left -1,1
	Label/W=$plotName left "Direction autocorrelation"
	Label/W=$plotName bottom "Time (min)"
	ErrorBars/W=$plotName $avName Y,wave=($errName,$errName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// Plot these summary windows at the end
	avName = "W_Ave_cd_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=cdPlot $avName
	ErrorBars/W=cdPlot $avName SHADE= {0,4,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=cdPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	avName = "W_Ave_iv_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=ivPlot $avName
	ErrorBars/W=ivPlot $avName SHADE= {0,4,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=ivPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	newName = pref + "ivHist"
	AppendToGraph/W=ivHPlot $newName
	ModifyGraph/W=ivHPlot rgb($newName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	avName = "W_Ave_dD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=dDPlot $avName
	ErrorBars/W=dDPlot $avName SHADE= {0,4,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=dDPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
			
	avName = "W_Ave_MSD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=MSDPlot $avName
	ErrorBars/W=MSDPlot $avName SHADE= {0,4,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=MSDPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	avName = "W_Ave_DA_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=DAPlot $avName
	ErrorBars/W=DAPlot $avName SHADE= {0,4,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=DAPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	// Tidy report
	DoWindow/F $layoutName
	// in case these are not captured as prefs
	LayoutPageAction size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
	ModifyLayout units=0
	ModifyLayout frame=0,trans=1
	Execute /Q "Tile"
	TextBox/C/N=text0/F=0/A=RB/X=0.00/Y=0.00 ReplaceString("_",pref,"")
	DoUpdate
End

// This function will make ImageQuilts of 2D tracks
/// @param qSize	Variable to indicate desired size of image quilt (qSize^2 tracks)
/// @param idealLength	Variable to indicate desired duration of tracks in minutes
Function MakeImageQuilt(qSize)
	Variable qSize
	
	WAVE/T condWave = root:condWave
	Variable cond = numpnts(condWave)
	Wave paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Wave colorWave = root:colorWave
	String condName, dataFolderName, wName
	Variable longestCond = 0 , mostFrames = 0
	
	Variable i
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		mostFrames = FindSolution()
		longestCond = max(longestCond,mostFrames)
	endfor
	SetDataFolder root:
	// Now they're all done, cycle again to find optimum quilt size
	Make/O/N=(longestCond,qSize+1,cond)/FREE optiMat
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		wName = "root:data:" + condName + ":solutionWave"
		Wave w0 = $wName
		optiMat[][][i] = (w0[p][0] >= q^2) ? 1 : 0
	endfor
	optiMat /= cond
	// make a 1D wave where row = qSize and value = frames that can be plotted for all cond
	MatrixOp/O/FREE quiltSizeMat = sumcols(floor(sumBeams(optiMat)))^t
	// find optimum
	quiltSizeMat *= p^2
	WaveStats/Q quiltSizeMat
	Variable optQSize = V_maxRowLoc
	Variable optDur = (V_max / V_maxRowLoc^2) - 1 // because 0-based
	Print qSize, "x", qSize, "quilt requested.", optQSize, "x", optQSize, "quilt with", optDur, "frames shown."
	
	String plotName
	Variable startVar,endVar,xShift,yShift
	Variable spaceVar = 100 // this might need changing
	Variable j
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		plotName = condName + "_quilt"
		KillWindow/Z $plotName
		Display/N=$plotName
		WAVE segValid, trackDurations
		WAVE/T trackNames
		segValid[] = (trackDurations[p] > optDur * tStep) ? p : NaN
		WaveTransform zapnans segValid
		StatsSample/N=(optQSize^2) segValid
		WAVE/Z W_Sampled
		Duplicate/O W_Sampled, segSelected
		Make/O/N=(optQSize^2)/T segNames
		Make/O/N=(optQSize^2) segLengths
		for(j = 0; j < optQSize^2; j += 1)
			segNames[j] = trackNames[segSelected[j]]
			wName = ReplaceString("tk_",segNames[j],"cd_") // get cum dist wave name
			Wave cdW0 = $wName
			segLengths[j] = cdW0[optDur] // store cum dist at point optDur
		endfor
		Sort segLengths, segLengths, segNames
		// plot segNamed waves out
		Make/O/N=(optQSize^2*(optDur+1),2) quiltBigMat = NaN
		for(j = 0; j < optQSize^2; j += 1)
			wName = segNames[j]
			Wave tkW0 = $wName
			// put each track into the big quilt wave leaving a NaN between each
			startVar = j * optDur + (j * 1)
			endVar = startVar + optDur - 1
			quiltBigMat[startVar,endVar][] = tkW0[p-startVar][q]
			xShift = mod(j,optQSize) * spaceVar
			yShift = floor(j/optQSize) * spaceVar
			quiltBigMat[startVar,endVar][0] += xShift
			quiltBigMat[startVar,endVar][1] += yShift
		endfor
		// Add to plot and then format
		AppendToGraph/W=$plotName quiltBigMat[][1] vs quiltBigMat[][0]
		SetAxis/W=$plotName left (optQsize+0.5) * spaceVar,-1.5*spaceVar
		SetAxis/W=$plotName bottom -1.5*spaceVar,(optQsize+0.5) * spaceVar
		ModifyGraph/W=$plotName width={Aspect,1}
		ModifyGraph/W=$plotName manTick={0,100,0,0},manMinor={0,0}
		ModifyGraph/W=$plotName noLabel=2,mirror=1,standoff=0,tick=3
		ModifyGraph/W=$plotName grid=1,gridRGB=(34952,34952,34952)
		ModifyGraph axRGB=(65535,65535,65535)
		ModifyGraph/W=$plotName rgb=(colorWave[i][0],colorWave[i][1],colorWave[i][2])
		ModifyGraph/W=$plotName margin=14
		// Append to appropriate layout (page 2)
		String layoutName = condName + "_layout"
		LayoutPageAction/W=$layoutName appendPage
		AppendLayoutObject/W=$layoutName/PAGE=(2) graph $plotName
	endfor
	SetDataFolder root:
End

Function FindSolution()
	String wList = WaveList("tk_*",";","")
	Variable nWaves = ItemsInList(wList)
	Make/O/N=(nWaves)/T trackNames
	Make/O/N=(nWaves) trackDurations, segValid
	Wave paramWave = root:paramWave
	Variable tStep = paramWave[1]
	String wName
	
	Variable i
	
	for(i = 0; i < nWaves; i += 1)
		wName = StringFromList(i,wList)
		trackNames[i] = wName
		Wave w0 = $wName
		trackDurations[i] = dimsize(w0,0) * tStep
	endfor
	
	// how many are longer than x hrs?
	Variable mostFrames = round(WaveMax(trackDurations) / tStep)
	Make/O/N=(mostFrames,nWaves) solutionMat
	// Find tracks that are longer than a given length of time
	solutionMat[][] = (trackDurations[q] > p * tStep) ? 1 : 0
	MatrixOp/O solutionWave = sumRows(solutionMat)
	return mostFrames
End

///////////////////////////////////////////////////////////////////////

///	@param	cond	number of conditions - determines size of box
Function myIO_Panel(cond)
	Variable cond
	
	Wave/Z colorWave = root:colorWave
	// make global text wave to store paths
	Make/T/O/N=(cond) condWave
	Make/T/O/N=(cond) PathWave1,PathWave2
	DoWindow/K FilePicker
	NewPanel/N=FilePicker/K=1/W=(40,40,840,150+30*cond)
	// labelling of columns
	DrawText/W=FilePicker 10,30,"Name"
	DrawText/W=FilePicker 160,30,"Cell tracking data (directory of CSVs or Excel file)"
	DrawText/W=FilePicker 480,30,"Optional: stationary data"
	DrawText/W=FilePicker 10,100+30*cond,"CellMigration"
	// do it button
	Button DoIt,pos={680,70+30*cond},size={100,20},proc=DoItButtonProc,title="Do It"
	// insert rows
	String buttonName1a,buttonName1b,buttonName2a,buttonName2b,boxName0,boxName1,boxName2
	Variable i
	
	for(i = 0; i < cond; i += 1)
		boxName0 = "box0_" + num2str(i)
		buttonName1a = "dir1_" + num2str(i)
		buttonName1b = "file1_" + num2str(i)
		boxName1 = "box1_" + num2str(i)
		buttonName2a = "dir2_" + num2str(i)
		buttonName2b = "file2_" + num2str(i)
		boxName2 = "box2_" + num2str(i)
		// row label
		DrawText/W=FilePicker 10,68+i*30,num2str(i+1)
		// condition label
		SetVariable $boxName0,pos={30,53+i*30},size={100,14},value= condWave[i], title=" "
		// dir button
		Button $buttonName1a,pos={160,50+i*30},size={38,20},proc=ButtonProc,title="Dir"
		// file button
		Button $buttonName1b,pos={200,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// file or dir box
		SetVariable $boxName1,pos={240,53+i*30},size={220,14},value= PathWave1[i], title=" "
		// stationary dir button
		Button $buttonName2a,pos={480,50+i*30},size={38,20},proc=ButtonProc,title="Dir"
		// stationary button
		Button $buttonName2b,pos={520,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// stationary or dir box
		SetVariable $boxName2,pos={560,53+i*30},size={220,14},value= PathWave2[i], title=" "
		SetDrawEnv fillfgc=(colorWave[i][0],colorWave[i][1],colorWave[i][2])
		DrawOval/W=FilePicker 130,50+i*30,148,68+i*30
	endfor
End

// define buttons
Function ButtonProc(ctrlName) : ButtonControl
	String ctrlName

	Wave/T PathWave1,PathWave2
	Variable refnum, wNum, ii
	String expr, wNumStr, iiStr, stringForTextWave

	if(StringMatch(ctrlName,"file*") == 1)
		expr="file([[:digit:]]+)\\w([[:digit:]]+)"
		SplitString/E=(expr) ctrlName, wNumStr, iiStr
		// get File Path
		Open/D/R/F="*.xls*"/M="Select Excel Workbook" refNum
		stringForTextWave = S_filename
	else
		expr="dir([[:digit:]]+)\\w([[:digit:]]+)"
		SplitString/E=(expr) ctrlName, wNumStr, iiStr
		// set outputfolder
		NewPath/O/Q DirOfCSVs
		PathInfo DirOfCSVs
		stringForTextWave = S_Path
	endif

	if (strlen(stringForTextWave) == 0) // user pressed cancel
		return -1
	endif
	wNum = str2num(wNumStr)
	ii = str2num(iiStr)
	if (wNum == 1)
		PathWave1[ii] = stringForTextWave
	else
		PathWave2[ii] = stringForTextWave
	endif
End

Function DoItButtonProc(ctrlName) : ButtonControl
	String ctrlName
 	
 	WAVE/T CondWave
	WAVE/T PathWave1
	Variable okvar = 0
	
	strswitch(ctrlName)	
		case "DoIt" :
			// check CondWave
			okvar = WaveChecker(CondWave)
			if (okvar == -1)
				Print "Error: Not all conditions have a name."
				break
			endif
			okvar = NameChecker(CondWave)
			if (okvar == -1)
				Print "Error: Two conditions have the same name."
				break
			endif
			okvar = WaveChecker(PathWave1)
			if (okvar == -1)
				Print "Error: Not all conditions have a file to load."
				break
			else
				Migrate()
			endif
	endswitch	
End

STATIC function WaveChecker(TextWaveToCheck)
	Wave/T TextWaveToCheck
	Variable nRows = numpnts(TextWaveToCheck)
	Variable len
	
	Variable i
	
	for(i = 0; i < nRows; i += 1)
		len = strlen(TextWaveToCheck[i])
		if(len == 0)
			return -1
		elseif(numtype(len) == 2)
			return -1
		endif
	endfor
	return 1
End

STATIC function NameChecker(TextWaveToCheck)
	Wave/T TextWaveToCheck
	Variable nRows = numpnts(TextWaveToCheck)
	Variable len
	
	Variable i,j
	
	for(i = 0; i < nRows; i += 1)
		for(j = 0; j < nRows; j += 1)
			if(j > i)
				if(cmpstr(TextWaveToCheck[i], TextWaveToCheck[j], 0) == 0)
					return -1
				endif
			endif
		endfor
	endfor
	return 1
End

///////////////////////////////////////////////////////////////////////

// Colours are taken from Paul Tol SRON stylesheet
// Define colours
StrConstant SRON_1 = "0x4477aa;"
StrConstant SRON_2 = "0x4477aa; 0xcc6677;"
StrConstant SRON_3 = "0x4477aa; 0xddcc77; 0xcc6677;"
StrConstant SRON_4 = "0x4477aa; 0x117733; 0xddcc77; 0xcc6677;"
StrConstant SRON_5 = "0x332288; 0x88ccee; 0x117733; 0xddcc77; 0xcc6677;"
StrConstant SRON_6 = "0x332288; 0x88ccee; 0x117733; 0xddcc77; 0xcc6677; 0xaa4499;"
StrConstant SRON_7 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0xddcc77; 0xcc6677; 0xaa4499;"
StrConstant SRON_8 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0xcc6677; 0xaa4499;"
StrConstant SRON_9 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0xcc6677; 0x882255; 0xaa4499;"
StrConstant SRON_10 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0x661100; 0xcc6677; 0x882255; 0xaa4499;"
StrConstant SRON_11 = "0x332288; 0x6699cc; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0x661100; 0xcc6677; 0x882255; 0xaa4499;"
StrConstant SRON_12 = "0x332288; 0x6699cc; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0x661100; 0xcc6677; 0xaa4466; 0x882255; 0xaa4499;"

/// @param hex		variable in hexadecimal
Function hexcolor_red(hex)
	Variable hex
	return byte_value(hex, 2) * 2^8
End

/// @param hex		variable in hexadecimal
Function hexcolor_green(hex)
	Variable hex
	return byte_value(hex, 1) * 2^8
End

/// @param hex		variable in hexadecimal
Function hexcolor_blue(hex)
	Variable hex
	return byte_value(hex, 0) * 2^8
End

/// @param data	variable in hexadecimal
/// @param byte	variable to determine R, G or B value
STATIC Function byte_value(data, byte)
	Variable data
	Variable byte
	return (data & (0xFF * (2^(8*byte)))) / (2^(8*byte))
End

/// @param	cond	variable for number of conditions
Function MakeColorWave(cond)
	Variable cond
	
	// Pick colours from SRON palettes
	String pal
	if(cond == 1)
		pal = SRON_1
	elseif(cond == 2)
		pal = SRON_2
	elseif(cond == 3)
		pal = SRON_3
	elseif(cond == 4)
		pal = SRON_4
	elseif(cond == 5)
		pal = SRON_5
	elseif(cond == 6)
		pal = SRON_6
	elseif(cond == 7)
		pal = SRON_7
	elseif(cond == 8)
		pal = SRON_8
	elseif(cond == 9)
		pal = SRON_9
	elseif(cond == 10)
		pal = SRON_10
	elseif(cond == 11)
		pal = SRON_11
	else
		pal = SRON_12
	endif
	
	Variable color,vR,vG,vB
	Make/O/N=(cond,3) root:colorwave
	WAVE colorWave = root:colorWave
	Variable i
	
	for(i = 0; i < cond; i += 1)
		// specify colours
		if(cond <= 12)
			color = str2num(StringFromList(i,pal))
			vR = hexcolor_red(color)
			vG = hexcolor_green(color)
			vB = hexcolor_blue(color)
		else
			color = str2num(StringFromList(round((i/cond) * 12),pal))
			vR = hexcolor_red(color)
			vG = hexcolor_green(color)
			vB = hexcolor_blue(color)
		endif
		colorwave[i][0] = vR
		colorwave[i][1] = vG
		colorwave[i][2] = vB
	endfor
End

STATIC Function CleanSlate()
	String fullList = WinList("*", ";","WIN:7")
	Variable allItems = ItemsInList(fullList)
	String name
	Variable i
 
	for(i = 0; i < allItems; i += 1)
		name = StringFromList(i, fullList)
		KillWindow/Z $name		
	endfor
	
	// Kill waves in root
	KillWaves/A/Z
	// Look for data folders and kill them
	DFREF dfr = GetDataFolderDFR()
	allItems = CountObjectsDFR(dfr, 4)
	for(i = 0; i < allItems; i += 1)
		name = GetIndexedObjNameDFR(dfr, 4, i)
		KillDataFolder $name		
	endfor
End

// This function reshuffles the plots so that they will be tiled (LR, TB) in the order that they were created
// From v 1.03 all plots are hidden so this function is commented out of workflow
Function OrderGraphs()
	String list = WinList("*", ";", "WIN:1")		// List of all graph windows
	Variable numWindows = ItemsInList(list)
	
	Variable i
	
	for(i = 0; i < numWindows; i += 1)
		String name = StringFromList(i, list)
		DoWindow /F $name
	endfor
End

// Function from aclight to retrieve #pragma version number
/// @param procedureWinTitleStr	This is the procedure window "LoadMigration.ipf"
Function GetProcedureVersion(procedureWinTitleStr)
	String procedureWinTitleStr
 
	// By default, all procedures are version 1.00 unless
	// otherwise specified.
	Variable version = 1.00
	Variable versionIfError = NaN
 
	String procText = ProcedureText("", 0, procedureWinTitleStr)
	if (strlen(procText) <= 0)
		return versionIfError		// Procedure window doesn't exist.
	endif
 
	String regExp = "(?i)(?:^#pragma|\\r#pragma)(?:[ \\t]+)version(?:[\ \t]*)=(?:[\ \t]*)([\\d.]*)"
 
	String versionFoundStr
	SplitString/E=regExp procText, versionFoundStr
	if (V_flag == 1)
		version = str2num(versionFoundStr)
	endif
	return version	
End