
--DECLARE START OF WEEK AND START / END DATE TIMES FOR REPORT
SET DATEFIRST 6;  --Set Saturday to be the start of the week
DECLARE @StartTime  DATETIME = DATEADD(DAY,-1,GETDATE());
DECLARE @EndTime DATETIME = GETDATE();


--CREATE TEMP TABLE TO GET THE LIST OF INSCOPE PROCESS ORDERS
IF OBJECT_ID('tempdb..#LOV') IS NOT NULL
DROP TABLE #LOV
CREATE TABLE #LOV
(
	PO varchar(255)
)
INSERT INTO #LOV
SELECT DISTINCT PO 
FROM [IEBALB81].[ONGData].[dbo].[Weights] T1 WITH (NOLOCK)
WHERE 
	[DateTime] BETWEEN @StartTime AND @EndTime 
	AND LINE IN ('Cetec 4A','Cetec 4B','Line 1A','Line 1B','Line 2A','Line 2B','Line 3A','Line 3B') 
	AND PO IS NOT NULL 
	AND LEN(PO)=12


--USING THE LIST OF PROCESS ORDERS FROM THE TEMP TABLE, OBTAIN THE BATCH FILLING DETAILS
IF OBJECT_ID('tempdb..#BATCHHIS_SUMMARY') IS NOT NULL
DROP TABLE #BATCHHIS_SUMMARY
CREATE TABLE #BATCHHIS_SUMMARY
(
	SKU varchar(255),
	SKU_DESCRIPTION varchar(255),
	Line varchar(40),
	PO varchar(255),
	Head varchar(40),
	[DateTime] DATETIME,
	PO_Weight FLOAT,
	RowID INT,
	PO_Rank INT,
	Head_rank INT,
	[Next_DT] DATETIME,
	TBW INT
)
INSERT INTO #BATCHHIS_SUMMARY
SELECT DISTINCT
	COALESCE(T2.PRODUCT_MATERIAL_NUMBER, T3.PRODUCT_MATERIAL_NUMBER) SKU, COALESCE(T2.PRODUCT_DESCRIPTION, T3.PRODUCT_DESCRIPTION) SKU_DESCRIPTION, Line, T1.[PO], Head, [DateTime],  ROUND(Weight,2) AS PO_Weight, RowID,
	DENSE_RANK() OVER (PARTITION BY Line, T1.PO, Head ORDER BY [DateTime] ASC) AS PO_Rank,
	DENSE_RANK() OVER (PARTITION BY Line, T1.PO ORDER BY Head ASC) AS Head_Rank,
	LEAD(DateTime) OVER (PARTITION BY Line, T1.PO, Head ORDER BY [DateTime] ASC) AS Next_DT, 
	DATEDIFF(SECOND, T1.DateTime, LEAD(DateTime) OVER (PARTITION BY Line, T1.PO, Head ORDER BY [DateTime] ASC)) AS TBW
FROM [IEBALB81].[ONGData].[dbo].[Weights] T1 WITH (NOLOCK)
LEFT JOIN [IEBALB106,2433].[BallinaDB].[dbo].[HEADER] T2 WITH (NOLOCK) ON T2.BATCHID = T1.PO
LEFT JOIN [BallinaDBArchive].[dbo].[HEADER] T3 WITH (NOLOCK) ON T3.BATCHID = T1.PO
WHERE PO IN (SELECT DISTINCT PO FROM #LOV)


--USING THE LIST OF PROCESS ORDERS FROM THE TEMP TABLE, OBTAIN THE TOTE CHANGE DETAILS (THIS WILL INCDICATE POTENTIAL DOWNTIME RELATED TO MATERIAL SUPPLY)
IF OBJECT_ID('tempdb..#TOTE_CHANGES') IS NOT NULL
DROP TABLE #TOTE_CHANGES
CREATE TABLE #TOTE_CHANGES
(
	BATCHID varchar(255),
	HEAD varchar(40),
	PHASE_START DATETIME,
	PHASE_END DATETIME,
	FILL_TIME INT
)
INSERT INTO #TOTE_CHANGES
SELECT DISTINCT BATCHID, LEFT([INSTRUCTION_STEP],CHARINDEX(',',[Instruction_Step])-1) [Head], DATEADD(MINUTE, DATEDIFF(MINUTE, 0, [Phase_Start]), 0) PHASE_START, PHASE_END, FILL_TIME
FROM [IEBALB106,2433].[I4_OEE].[dbo].[DRYPARTS_TOTE_CHANGE_DATA] T1
INNER JOIN #BATCHHIS_SUMMARY T2 ON T1.BATCHID = T2.PO AND LEFT(T1.[INSTRUCTION_STEP],CHARINDEX(',',T1.[Instruction_Step])-1) = T2.[HEAD]


--USING THE LIST OF PROCESS ORDERS FROM THE TEMP TABLE, OBTAIN ALL OEE DOWNTIME DETAILS ENTERED IN THE SYSTEM FROM THE TEAMS
IF OBJECT_ID('tempdb..#OEE_DOWNTIME') IS NOT NULL
DROP TABLE #OEE_DOWNTIME
CREATE TABLE #OEE_DOWNTIME
(
	Zone varchar(40),
	PO varchar(255),
	LineName varchar(40),
	EquipmentName varchar(255),
	EventType varchar(255),
	State varchar(255),
	StateDescription varchar(255),
	ReasonGroup varchar(255),
	Reason varchar(255),
	Comment varchar(1000),
	EventTime DATETIME, 
	RunTime INT,
	Downtime INT,
	IdleTime INT,
	TotalTime INT
)
INSERT INTO #OEE_DOWNTIME
SELECT DISTINCT 
		T2.Zone, T1.WorkOrderID AS PO, T1.LineName, T1.EquipmentName, T1.EventType, T1.State, T1.StateDescription, T1.ReasonGroup, T1.Reason, T1.Comment, 
		/*DATEADD(mi, DATEDIFF(mi, 0, EventTime), 0)*/ EventTime,  RuntimeDuration as RunTime, DowntimeDuration AS Downtime, IdletimeDuration AS IdleTime, (RuntimeDuration+DowntimeDuration+IdletimeDuration) TotalTime
	FROM [IEBALB81].[Intelligence].[dbo].[vwUtilization] T1 WITH (NOLOCK)
	INNER JOIN #LOV T3 ON T1.WorkOrderID = T3.PO
	LEFT JOIN
			(SELECT LineName, EquipmentName, Zone
			FROM
			(VALUES ('Cetec 4A','C4A_AZO','0-Upstairs'),('Cetec 4A','C4A_BagMaker','1'),('Cetec 4A','C4A_Case1_BoxMaker','2'),('Cetec 4A','C4A_Case1_LineControl','2'),('Cetec 4A','C4A_Case1_Palletiser','2'),('Cetec 4A','C4A_Case2_BoxMaker','2'),('Cetec 4A','C4A_Case2_LineControl','2'),('Cetec 4A','C4A_Case2_Palletiser','2'),('Cetec 4A','C4A_CaseWrapper','2'),('Cetec 4A','C4A_Checkweigher','1'),('Cetec 4A','C4A_Fillers4A','1'),('Cetec 4A','C4A_FillHead1','1'),('Cetec 4A','C4A_FillHead2','1'),('Cetec 4A','C4A_FillHead3','1'),('Cetec 4A','C4A_FillHead4','1'),('Cetec 4A','C4A_FillHead5','1'),('Cetec 4A','C4A_FillHead6','1'),('Cetec 4A','C4A_Line4A','2'),('Cetec 4A','C4A_Totes','0-Upstairs'),('Cetec 4A','C4A_WashRoom','0-Upstairs'),('Cetec 4B','C4B_BagMaker','1'),('Cetec 4B','C4B_Fillers4B','1'),('Cetec 4B','C4B_FillHead1','1'),('Cetec 4B','C4B_FillHead2','1'),('Cetec 4B','C4B_FillHead3','1'),('Cetec 4B','C4B_FillHead4','1'),('Cetec 4B','C4B_FillHead5','1'),('Cetec 4B','C4B_FillHead6','1'),('Cetec 4B','C4B_Line4B','2'),('Cetec 4B','C4B_Totes','0-Upstairs'),('Cetec 4C','C4C_BagMaker','1'),('Cetec 4C','C4C_BagOutfeed','1'),('Cetec 4C','C4C_Fillers4C','1'),('Cetec 4C','C4C_Totes','0-Upstairs'),('Line 4E','C4E_Bagmaker','1'),('Line 4E','C4E_BagOutfeed','1'),('Line 4E','C4E_Filler','1'),('Line 4E','C4E_Totes','0-Upstairs')) Zones(LineName, EquipmentName,Zone)
			) T2 ON T1.EquipmentName = T2.EquipmentName
	WHERE
		([DowntimeDuration] >0 OR RuntimeDuration >0 OR IdletimeDuration >0)
		AND (T1.EquipmentName LIKE '%C4[A-B]_Fillers4[A-B]%')
		AND (StateDescription <> 'Running' AND ReasonGroup <> 'Running' AND Reason <> 'Running')


/* --------------------------------------------------------------------------------------------------------------------------------------------------------------------- */
/* --------------------------------------------------------------------------------------------------------------------------------------------------------------------- */
/* --------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

--FIRST CTE TO OBTAIN THE 'LOWEST REPEATING FILLING TIME', THIS SI BASED ON THE MOST COMMON VALUE
;with 
PROCESS_CONTROL
AS
(
	SELECT 
		PO_DETAILS.*,
		PO_STATS.[PO_Start],
		PO_STATS.[PO_End],
		(CASE WHEN [PO_WEIGHT] <0 THEN 1 ELSE 0 END) AS [Bad data],
		PO_STATS.Min_TBW,
		PO_STATS.Avg_TBW,
		PO_STATS.STDEV_TBW,
		PO_STATS2.LOWEST_REPEATABLE_TIME,
		(CASE WHEN PO_DETAILS.TBW IS NULL THEN 'IGNORE' WHEN PO_DETAILS.TBW >= PO_STATS2.LOWEST_REPEATABLE_TIME*5 THEN 'Y' WHEN (PO_DETAILS.TBW BETWEEN (PO_STATS.Avg_TBW - PO_STATS.STDEV_TBW) AND (PO_STATS.Avg_TBW + PO_STATS.STDEV_TBW)) THEN 'N' ELSE 'Y' END) AS [POSSIBLE LINE STOPPAGE], /* Think about simply adding 1 minute to the mean */
		(CASE WHEN PO_DETAILS.TBW IS NULL THEN 'IGNORE' WHEN PO_DETAILS.TBW >= PO_STATS2.LOWEST_REPEATABLE_TIME*5 THEN 'Y' WHEN (PO_DETAILS.TBW BETWEEN (PO_STATS.Avg_TBW - PO_STATS.STDEV_TBW) AND (PO_STATS.Avg_TBW + PO_STATS.STDEV_TBW)) THEN 'N' ELSE 'Y' END) AS [DOWNTIME],
		(CASE WHEN PO_DETAILS.TBW > PO_STATS2.LOWEST_REPEATABLE_TIME THEN PO_DETAILS.TBW - PO_STATS2.LOWEST_REPEATABLE_TIME ELSE 0 END) AS Lost_time
	FROM #BATCHHIS_SUMMARY PO_DETAILS
		LEFT JOIN
		(
			SELECT 
				Line, PO,
				MIN(TBW) AS Min_TBW,
				AVG(TBW) AS Avg_TBW, 
				ROUND(STDEV(TBW),1) AS STDEV_TBW,
				MIN(DateTime) AS [PO_Start],
				MAX(DateTime) AS [PO_End]
			FROM #BATCHHIS_SUMMARY
			WHERE TBW IS NOT NULL
			GROUP BY Line, PO --, Head
		) PO_STATS ON PO_DETAILS.PO = PO_STATS.PO AND PO_DETAILS.LINE = PO_STATS.LINE --AND PO_DETAILS.Head = PO_STATS.Head
		LEFT JOIN
		(
			SELECT DISTINCT PO, TBW AS LOWEST_REPEATABLE_TIME, COUNT(*) AS [REC_COUNT], ROW_NUMBER() OVER (PARTITION BY PO ORDER BY COUNT(*) DESC, TBW ASC) AS LRT_Rank
			FROM #BATCHHIS_SUMMARY
			GROUP BY PO, TBW
		) PO_STATS2 ON PO_DETAILS.PO = PO_STATS2.PO AND PO_STATS2.LRT_Rank = 1
)

--SECOND CTE TO CONNECT THE FILLING DETAILS WITH THE OEE DOWNTIME
,
DRYPARTS_PERFORMANCE AS
(
--DETAIL QUERY
	SELECT DISTINCT
	--Bag fill details
		SKU, SKU_DESCRIPTION, Line, T1.PO, Head, Head_Rank, PO_Weight [FILL_WEIGHT], DateTime [FILL_DATETIME], Next_DT, PO_Rank [FILL_NO], TBW [FILL_TIME], MIN_TBW, LOWEST_REPEATABLE_TIME [TARGET_FILLTIME], Avg_TBW, STDEV_TBW, [Possible Line Stoppage] [STOPPAGE], Lost_time [STOPPED_TIME], T1.[DOWNTIME] AS [Downtime Flag],
	--OEE RunTime/Downtime details
		T2.Zone,
		T2.EquipmentName,
		T2.EventTime,
		(CASE WHEN T1.[Downtime] ='N' AND T1.Lost_Time=0 THEN 'Line running <= LRT' WHEN T1.[Downtime]='N' AND T1.Lost_Time >0 THEN 'Line running slow > LRT' WHEN T1.[Downtime] ='Y' AND T1.Lost_Time >0 THEN ISNULL(T2.StateDescription,'Stopped') ELSE 'OTHER' END) AS StateDescription,
		(CASE WHEN T1.[Downtime] ='N' AND T1.Lost_Time=0 THEN 'Line running <= LRT' WHEN T1.[Downtime]='N' AND T1.Lost_Time >0 THEN 'Line running slow > LRT' WHEN T1.[Downtime] ='Y' AND T1.Lost_Time >0 THEN ISNULL(T2.ReasonGroup,'Downtime') ELSE 'OTHER' END) AS ReasonGroup,
		(CASE WHEN T1.[Downtime] ='N' AND T1.Lost_Time=0 THEN 'Line running <= LRT' WHEN T1.[Downtime]='N' AND T1.Lost_Time >0 THEN 'Line running slow > LRT' WHEN T1.[Downtime] ='Y' AND T1.Lost_Time >0 THEN ISNULL(T2.Reason,'Unknown') ELSE 'OTHER'END) AS Reason,
		NULL [Comment] /*T2.Comment*/, T2.RunTime, T2.Downtime, T2.IdleTime,
		ROW_NUMBER() OVER (PARTITION BY T1.PO, Head, [DateTime] ORDER BY CASE WHEN T2.StateDescription ='Offline'THEN T2.IdleTime ELSE T2.DOWNTIME END DESC) AS PO_DOWNTIMEREASON_NO
	FROM PROCESS_CONTROL T1 
	LEFT JOIN #OEE_DOWNTIME T2 ON T1.PO = T2.PO AND (T1.[POSSIBLE LINE STOPPAGE] = 'Y' OR T1.DOWNTIME = 'Y') AND T2.EventTime BETWEEN T1.[DateTime] AND T1.Next_DT AND T1.Lost_time >= T2.TotalTime
	WHERE Head_Rank = 1 
)


--FINAL OUTPUT QUERY
SELECT DISTINCT
	GETDATE() [created], GETDATE() [modified], T1.SKU, T1.SKU_DESCRIPTION, T1.[LINE], T1.[PO], T1.[HEAD], T1.[FILL_WEIGHT], T1.[FILL_NO], T1.[FILL_DATETIME], T1.[FILL_TIME], T1.[TARGET_FILLTIME], T1.[STOPPAGE], T1.[STOPPED_TIME], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN T1.[FILL_DATETIME] ELSE T1.[EVENTTIME] END [EVENTTIME], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN 'Infeed Breakdown' ELSE (CASE WHEN T2.PHASE_START IS NULL AND T1.[REASONGROUP]='Infeed Breakdown' THEN 'Downtime' ELSE T1.[REASONGROUP] END) END [REASONGROUP], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN 'Tote Change' ELSE (CASE WHEN T2.PHASE_START IS NULL AND T1.[REASON]='Tote Change' THEN 'Unknown Reason' ELSE T1.[REASON] END) END [REASON], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN NULL ELSE T1.[COMMENT] END [COMMENT], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN 0 ELSE T1.[RUNTIME] END [RUNTIME], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN T1.FILL_TIME ELSE T1.[DOWNTIME] END [DOWNTIME], 
	CASE WHEN T2.PHASE_START IS NOT NULL THEN 1 ELSE T1.PO_DOWNTIMEREASON_NO END [PO_DOWNTIMEREASON_NO]
FROM DRYPARTS_PERFORMANCE T1
LEFT JOIN #TOTE_CHANGES T2 WITH (NOLOCK) ON 
										T1.[PO] = T2.[BATCHID] AND 
										T1.[Head] = T2.[Head] AND 
										T1.FILL_TIME BETWEEN T2.FILL_TIME-5 AND T2.FILL_TIME+5 AND
										(DATEADD(MINUTE,-1, DATEADD(MINUTE, DATEDIFF(MINUTE, 0, T1.[FILL_DATETIME]), 0)) = T2.PHASE_START OR DATEADD(MINUTE, DATEDIFF(MINUTE, 0, T1.[FILL_DATETIME]), 0) = T2.PHASE_START OR DATEADD(MINUTE,1, DATEADD(MINUTE, DATEDIFF(MINUTE, 0, T1.[FILL_DATETIME]), 0)) = T2.PHASE_START)
ORDER BY T1.[Line], T1.[PO], T1.[FILL_DATETIME], CASE WHEN T2.PHASE_START IS NOT NULL THEN 1 ELSE T1.PO_DOWNTIMEREASON_NO END


