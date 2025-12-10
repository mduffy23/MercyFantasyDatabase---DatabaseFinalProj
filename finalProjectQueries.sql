-- Part 3
-- Aggregation on one table
/* Interpretation:
    This query aggregates total points for each player by season from each player in the roster table.
    I cast the sum to numeric since round does not take double precision values as an argument.
*/
 SELECT 
    season,
    player_name,
    player_id,
    round(sum(points)::numeric, 4) AS points
FROM player_info.detailed_roster
GROUP BY season, player_name, player_id
;

-- Multi-table join (Inner Join)
/* Interpretation:
    This query joins a few tables to get to show which manager picked up players and the total points they scored.
    Waivers has a team key, which is also tracked in the managers table, which allows us to get the manager_guid associated 
    with each waiver transaction. The manager_map regularizes the manager names since some managers have used different yahoo
    accounts over the years. The seasonalpoints table simply joins the player_id and season to get the season point totals per player.
*/
SELECT W.Season, MM.propername as Manager, W.trade_id, W.timestamp, W.status, W.Type, W.Player, W.Player_ID, W.Pos, W.team_abbr, SP.Points as SeasonPoints
From transactions.Waivers W
Inner Join manager_info.manager_seasons M on W.team_key = M.team_key
Inner Join manager_map MM on MM.manager_guid = M.manager_guid
Inner Join seasonalpoints SP on W.season = SP.season and W.player_id = SP.player_id
Order By W.timestamp
;

-- Subquery
/* Interpretation:
    This query first performs a subquery to get all seasonal performances for the players. The outer
    query then selects the maximum points to return the the amount of points scored in a player's best
    season. Subquery is necessary here since we need to first aggregate by player and season before we can
    find the maximum points scored in a single season.
*/
Select player_name, player_id, Max(Points) as TotalPoints
From (
SELECT Season, Player_name, Player_id, Round(Sum(points)::numeric, 4) as Points
FROM player_info.detailed_roster
Group By Season, Player_name, Player_id
)
Group By player_name, player_id
Order By TotalPoints Desc
;

-- Window or Analytic Function
/* Interpretation:
    This query uses a window function to calculate the season-to-date points for each offensive player. The Partion By
    is similar to a group by, so the value is the sum of the player's points in that season. I round to avoid long decimals
    (must case to numeric first since round does not take double precision as an argument). The window function allows to keep
    each row, but also display an aggregated value.
*/
Select r.season, r.week, r.player_name, case when NFL.position = 'FB' Then 'RB' else NFL.position end as position, NFL.team as NFL_Team, NFL.opponent_team as NFL_Opposing_Team, r.pass_yds, r.pass_td, r.pass_int, r.rush_att, r.rush_yds, r.rush_td, r.targets, r.rec, r.rec_yds, r.rec_td, r.two_pt_conversion, r.fum_lost, r.points,
ROUND((SUM(points) OVER (PARTITION BY r.season, r.player_name))::numeric, 2) As Season_To_Date_Points
From player_info.detailed_roster R 
Left Join player_info.roster_reference NFL On R.season = NFL.season and R.week = NFL.week and NFL.player_name = r.player_name
Where r.position_type = 'O'
And (NFL.player_name is not null and r.points != 0) -- Bye week
Order By Season, Week, Season_To_Date_Points
;

-- CTE Usage
/* Interpretation:
    This query uses a CTE to calculate the average points a successfully traded player scored in a given season. The outer query then
    joins the CTE to itself to get the teams involved in each trade on the same row, which makes it possible to calculate the  average 
    point differential on the trade. The final output is ordered by the point differential in descending order to show the most lopsided trades first.
*/
With TradeTotalPoints as(
SELECT T.Season, T.Trade_ID, T.to_team as Team, T.to_team_key as Team_Key, Round(Avg(P.points)::numeric, 4) as Points
FROM transactions.trades T
Left Join SeasonalPoints P On t.season = p.season and t.player_id = p.player_id
Where T.status = 'successful'
Group By T.Season, T.Trade_ID, T.to_team, T.to_team_key
) 
Select F.Season, F.Trade_ID, F.Team as Team_One, F.Team_Key as Team_One_Key, F.Points as Team_One_Points, S.Team as Team_Two, S.Team_Key as Team_Two_Key, S.Points as Team_Two_Key,
F.Points - S.Points as Differential
From TradeTotalPoints F
Left Join TradeTotalPoints S On F.Season = S.Season and F.Trade_ID = S.Trade_ID and F.Team_Key != S.Team_Key
Where F.Points - S.Points > 0
Group By F.Season, F.Trade_ID, F.Team, F.Team_Key, F.Points, S.Team, S.Team_Key, S.Points
Order By Differential Desc
;

-- Derived metric updated with ALTER TABLE + UPDATE
/* Interpretation:
    These queries first alter the table to add a new float column called NoPPR_Points. Then an update
    query sets that column equal to the points column minus the receptions column, which is the
    non points-per-reception scoring format. That column can help show how much a player relies on their
    receptions for points.
*/
ALTER TABLE player_info.detailed_roster
ADD COLUMN NoPPR_Points float
;

UPDATE player_info.detailed_roster
SET NoPPR_Points = Points - Rec
;

-- Index-usage demonstration with EXPLAIN (before/after)
/* Interpretation:
    These queries first use EXPLAIN to show the query plan for selecting all rows from the roster_reference
    table where the season is 2025. The initial query plan shows a sequential scan, which means the database
    is scanning the entire table to find matching rows. After creating an index on the season column, the 
    second EXPLAIN shows that the query plan now uses an index scan, which is more efficient since it can
    quickly locate the rows for season 2025 using the index.

*/

-- Before Index
Explain 
Select *
From player_info.roster_reference
Where season = 2025
;

/* Output
Seq Scan on roster_reference  (cost=0.00..1019.43 rows=12443 width=30)
  Filter: (season = 2025)
*/

-- After Index
Create Index idx_season
On player_info.roster_reference (season)
;

Explain 
Select *
From player_info.roster_reference
Where season = 2025
;

/* Output
Index Scan using idx_season on roster_reference  (cost=0.29..367.04 rows=12443 width=30)
  Index Cond: (season = 2025)
*/

-- Creation of a materialized view or standard view + refresh strategy
/* Interpretation:
    This query creates a materialized view of a report that shows what the current matchups are  
    along with the lifetime record between the managers across all seasons. Since it is not possible
    to know which manager will be in which position (projected winner or projected loser), the query does
    two different joins to the lifetimerecord table so it will always catch the match ups lifetime record.
    Lifetimerecord has a pairing of every manager with the win and loss unless a manager has never lost to 
    another manager, so, in that case, that entry would not exist and the opposite pairing should be used.
    The query uses COALESCE to select the backup value if the first value is null. The query also
    uses the matchuphistory table to find the smallest and largest point differentials in the matchup history
    between the two managers. Again, we do not know the order the entries will come in since they are based on 
    the managers who won and lost in the given matchups, so the query uses an OR condition to flexibly join on
    the pairing. Finally, the outer query also joins the matchuphistory table twice to get the details of the matchups
    with the smallest and largest point differentials. With python, they can generate a report like this:
    Week 13 of the 2025 season

    - Chris vs Daniel 
        - Lifetime record (2-2)
        - Smallest point differential 20.22 (Chris beat Daniel 151.58 to 131.36 in week 13 of the 2024 season)
        - Largest point differential 68.32 (Daniel beat Chris 176.4 to 108.08 in week 7 of the 2023 season)

    - Joseph vs John 
        - Lifetime record (2-2)
        - Smallest point differential 17.62 (John beat Joseph 146.94 to 129.32 in week 13 of the 2024 season)
        - Largest point differential 33.82 (Joseph beat John 123.54 to 89.72 in week 7 of the 2023 season)

    - Billy vs Liam 
        - Lifetime record (1-0)
        - Smallest point differential 15.66 (Billy beat Liam 164.76 to 149.1 in week 4 of the 2025 season)
        - Largest point differential 15.66 (Billy beat Liam 164.76 to 149.1 in week 4 of the 2025 season)

    - Nick vs Duffy 
        - Lifetime record (3-1)
        - Smallest point differential 5.3 (Nick beat Duffy 155.0 to 149.7 in week 9 of the 2023 season)
        - Largest point differential 43.48 (Nick beat Duffy 171.96 to 128.48 in week 4 of the 2025 season)

    - Skyler vs Frankie 
        - Lifetime record (4-2)
        - Smallest point differential 0.46 (Skyler beat Frankie 141.04 to 140.58 in week 5 of the 2024 season)
        - Largest point differential 53.44 (Skyler beat Frankie 184.88 to 131.44 in week 5 of the 2023 season)
*/

Create MATERIALIZED View mv_weekly_report As
Select S.*, 
HS.Season as Season_S, HS.Week as Week_S, HS.winningmanager as WinningManager_S, HS.winningpoints as WinningPoints_S,   
HS.losingmanager as LosingManager_S, HS.Losingpoints as LosingPoints_S,
HL.Season as Season_L, HL.Week as Week_L, HL.winningmanager as WinningManager_L, HL.winningpoints as WinningPoints_L,   
HL.losingmanager as LosingManager_L, HL.Losingpoints as LosingPoints_L
From (
Select M.Season, M.Week, M.projectedwinningmanager, M.projectedlosingmanager, COALESCE(R.Wins, RFallBack.Losses, 0) as LifetimeWins, COALESCE(R.Losses, RFallBack.Wins, 0) as LifetimeLosses, COALESCE(Min(H.pointdiff), 0) as SmallestPointDifferential, COALESCE(Max(H.pointdiff), 0) as LargestPointDifferential
from vw_currentmatchup M
Left Join lifetimerecord R On M.projectedwinningmanager = R.winningmanager and M.projectedlosingmanager = R.losingmanager
Left Join lifetimerecord RFallBack On M.projectedwinningmanager = RFallBack.losingmanager and M.projectedlosingmanager = RFallBack.winningmanager 
Left Join matchuphistory H On (M.projectedwinningmanager = H.winningmanager or M.projectedwinningmanager = H.losingmanager) and (M.projectedlosingmanager = H.losingmanager or M.projectedlosingmanager = H.winningmanager)
Group By M.Season, M.Week, M.projectedwinningmanager, M.projectedlosingmanager, COALESCE(R.Wins, RFallBack.Losses, 0), COALESCE(R.Losses, RFallBack.Wins, 0)
) S
Left Join matchuphistory HL On S.LargestPointDifferential = HL.pointdiff and (S.projectedwinningmanager = HL.winningmanager or S.projectedwinningmanager = HL.losingmanager) and (S.projectedlosingmanager = HL.losingmanager or s.projectedlosingmanager = HL.winningmanager)
Left Join matchuphistory HS On S.SmallestPointDifferential = HS.pointdiff and (S.projectedwinningmanager = HS.winningmanager or S.projectedwinningmanager = HS.losingmanager) and (S.projectedlosingmanager = HS.losingmanager or s.projectedlosingmanager = HS.winningmanager)
;