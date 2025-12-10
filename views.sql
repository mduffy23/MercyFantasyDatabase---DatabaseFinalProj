-- View: public.vw_currentmatchup
CREATE OR REPLACE VIEW public.vw_currentmatchup AS
SELECT
    season,
    week,
    playoffs,
    projectedwinningmanager,
    winningprojpoints,
    projectedlosingmanager,
    losingprojpoints,
    MIN(pointdifferential) AS pointdiff
FROM (
    SELECT
        w.season,
        w.week,
        w.is_playoff AS playoffs,
        w.team_name AS winningteam,
        wm.propername AS projectedwinningmanager,
        w.projected_points AS winningprojpoints,
        l.team_name AS losingteam,
        wl.propername AS projectedlosingmanager,
        l.projected_points AS losingprojpoints,
        ROUND((w.projected_points - l.projected_points)::NUMERIC, 3) AS pointdifferential
    FROM manager_info.currentmatchup w
    LEFT JOIN manager_map wm
        ON w.manager_nickname::TEXT = wm.manager_nickname::TEXT
    LEFT JOIN manager_info.currentmatchup l
        ON w.week = l.week
        AND w.week_start = l.week_start
        AND w.week_end = l.week_end
        AND w.matchup_id = l.matchup_id
        AND w.manager_id <> l.manager_id
    LEFT JOIN manager_map wl
        ON l.manager_nickname::TEXT = wl.manager_nickname::TEXT
    WHERE ROUND((w.projected_points - l.projected_points)::NUMERIC, 3) > 0
) AS unnamed_subquery
GROUP BY
    season,
    week,
    playoffs,
    projectedwinningmanager,
    winningprojpoints,
    projectedlosingmanager,
    losingprojpoints
ORDER BY MIN(pointdifferential) DESC;


-- View: public.offensivescores
CREATE OR REPLACE VIEW public.offensivescores AS
WITH offensive_score AS (
    SELECT
        r.season,
        r.week,
        m_1.propername AS manager_name,
        SUM(r.points) AS o_points
    FROM player_info.detailed_roster r
    LEFT JOIN manager_map m_1
        ON r.manager_guid::TEXT = m_1.manager_guid::TEXT
    WHERE r.played_position::TEXT <> ALL (ARRAY['BN','K','DEF','IR'])
    GROUP BY r.season, r.week, m_1.propername
)
SELECT
    m.season,
    m.week,
    m.winningmanager,
    ROUND(w.o_points::NUMERIC, 2) AS winning_o_points,
    m.losingmanager,
    ROUND(l.o_points::NUMERIC, 2) AS losing_o_points
FROM matchuphistory m
LEFT JOIN offensive_score w
    ON w.season = m.season
    AND w.week = m.week
    AND w.manager_name = m.winningmanager
LEFT JOIN offensive_score l
    ON l.season = m.season
    AND l.week = m.week
    AND l.manager_name = m.losingmanager;


-- View: public.nfl_reference
CREATE OR REPLACE VIEW public.nfl_reference AS
SELECT
    season,
    week,
    home_team,
    away_team,
    weekday,
    gametime,
    game_type,
    roof,
    wind,
    temp,
    stadium,
    div_game
FROM nfl_schedule;


-- View: public.matchuphistory
CREATE OR REPLACE VIEW public.matchuphistory AS
SELECT
    season,
    week,
    playoffs,
    winningmanager,
    winningpoints,
    losingmanager,
    losingpoints,
    MIN(pointdifferential) AS pointdiff
FROM (
    SELECT
        TO_CHAR(w.week_start::TIMESTAMP WITH TIME ZONE, 'YYYY')::INTEGER AS season,
        w.week,
        w.is_playoff AS playoffs,
        w.team_name AS winningteam,
        wm.propername AS winningmanager,
        w.points AS winningpoints,
        l.team_name AS losingteam,
        wl.propername AS losingmanager,
        l.points AS losingpoints,
        ROUND((w.points - l.points)::NUMERIC, 3) AS pointdifferential
    FROM manager_info.matchups w
    LEFT JOIN manager_map wm
        ON w.manager_nickname::TEXT = wm.manager_nickname::TEXT
    LEFT JOIN manager_info.matchups l
        ON w.week = l.week
        AND w.week_start = l.week_start
        AND w.week_end = l.week_end
        AND w.matchup_id = l.matchup_id
        AND l.winner::TEXT = 'false'
    LEFT JOIN manager_map wl
        ON l.manager_nickname::TEXT = wl.manager_nickname::TEXT
    WHERE w.winner::TEXT = 'true'
) AS matchupsummary
GROUP BY
    season,
    week,
    playoffs,
    winningmanager,
    winningpoints,
    losingmanager,
    losingpoints
ORDER BY MIN(pointdifferential) DESC;


-- View: public.straightrecord
CREATE OR REPLACE VIEW public.straightrecord AS
SELECT
    winningmanager,
    losingmanager,
    COUNT(pointdiff) AS games
FROM matchuphistory
GROUP BY winningmanager, losingmanager;


-- View: public.lifetimerecord
CREATE OR REPLACE VIEW public.lifetimerecord AS
SELECT
    w.winningmanager,
    w.losingmanager,
    COALESCE(w.games, 0) AS wins,
    COALESCE(l.games, 0) AS losses
FROM straightrecord w
LEFT JOIN straightrecord l
    ON w.winningmanager = l.losingmanager
    AND w.losingmanager = l.winningmanager
ORDER BY w.winningmanager;


-- View: public.standingsbyseason
CREATE OR REPLACE VIEW public.standingsbyseason AS
SELECT
    w.season,
    w.winningmanager AS manager,
    COUNT(*) AS wins,
    l.losses
FROM matchuphistory w
LEFT JOIN (
    SELECT
        season,
        losingmanager,
        COUNT(*) AS losses
    FROM matchuphistory
    WHERE playoffs = 0
    GROUP BY season, losingmanager
) l
    ON w.season = l.season
    AND w.winningmanager = l.losingmanager
WHERE w.playoffs = 0
GROUP BY w.season, w.winningmanager, l.losses
ORDER BY COUNT(*) DESC;


-- View: public.player_reference
CREATE OR REPLACE VIEW public.player_reference AS
SELECT
    r.season,
    r.player_name,
    nfl.position,
    nfl.team AS nfl_team
FROM player_info.detailed_roster r
LEFT JOIN player_info.roster_reference nfl
    ON r.season = nfl.season
    AND r.week = nfl.week
    AND r.player_name::TEXT = nfl.player_name::TEXT
WHERE r.position_type::TEXT = 'O'
    AND nfl.player_name IS NOT NULL
GROUP BY r.season, r.player_name, nfl.position, nfl.team
ORDER BY r.season;


-- View: public.manager_map
CREATE OR REPLACE VIEW public.manager_map AS
SELECT
    manager_guid,
    manager_nickname,
    CASE
        WHEN manager_nickname::TEXT LIKE 'dan' THEN 'Daniel'
        WHEN manager_nickname::TEXT LIKE 'Matthew' THEN 'Duffy'
        ELSE INITCAP(manager_nickname::TEXT)
    END AS propername
FROM manager_info.managers;


-- View: public.seasonalpoints
CREATE OR REPLACE VIEW public.seasonalpoints AS
SELECT
    season,
    player_name,
    player_id,
    ROUND(SUM(points)::NUMERIC, 4) AS points
FROM roster
GROUP BY season, player_name, player_id;