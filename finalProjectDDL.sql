-- Part 1.B
BEGIN;

-- Managers table
CREATE TABLE IF NOT EXISTS manager_info.managers (
    manager_guid VARCHAR(50) NOT NULL PRIMARY KEY,
    manager_nickname VARCHAR(50)
);

-- Manager Seasons table
CREATE TABLE IF NOT EXISTS manager_info.manager_seasons (
    manager_guid VARCHAR(50),
    season INT,
    league_id VARCHAR(50),
    team_id INT,
    team_key VARCHAR(50) NOT NULL PRIMARY KEY,
    number_of_moves INT,
    number_of_trades INT,
    CONSTRAINT fk_manager_seasons_guid FOREIGN KEY (manager_guid)
        REFERENCES manager_info.managers(manager_guid)
        ON DELETE CASCADE
);

-- Current Matchup table
CREATE TABLE IF NOT EXISTS manager_info.currentmatchup (
    week INT NOT NULL,
    week_start DATE,
    week_end DATE,
    is_playoff INT,
    matchup_id INT,
    team_id INT,
    team_name VARCHAR(100),
    team_key VARCHAR(50),
    manager_id INT,
    manager_nickname VARCHAR(50),
    manager_guid VARCHAR(50) NOT NULL,
    projected_points DOUBLE PRECISION,
    season INT NOT NULL,
    PRIMARY KEY (season, week, manager_guid),
    CONSTRAINT fk_currentmatchup_manager FOREIGN KEY (manager_guid)
        REFERENCES manager_info.managers(manager_guid)
        ON DELETE CASCADE
);

-- Detailed Roster table
CREATE TABLE IF NOT EXISTS player_info.detailed_roster (
    season INT NOT NULL,
    week INT NOT NULL,
    team_key VARCHAR(100),
    team_name VARCHAR(100),
    manager_guid VARCHAR(50) NOT NULL,
    manager_name VARCHAR(50),
    player_id INT NOT NULL,
    player_name VARCHAR(100),
    played_position VARCHAR(10),
    position_type VARCHAR(5),
    pass_yds INT,
    pass_td INT,
    pass_int INT,
    rush_att INT,
    rush_yds INT,
    rush_td INT,
    targets INT,
    rec INT,
    rec_yds INT,
    rec_td INT,
    offensive_ret_td INT,
    two_pt_conversion INT,
    fum_lost INT,
    fum_ret_td INT,
    fg_0_19 INT,
    fg_20_29 INT,
    fg_30_39 INT,
    fg_40_49 INT,
    fg_50_plus INT,
    pat_made INT,
    pts_allow INT,
    sack INT,
    dt_int INT,
    fum_rec INT,
    dt_td INT,
    safe INT,
    blk_kick INT,
    dt_ret_td INT,
    pts_allow_0 INT,
    pts_allow_1_6 INT,
    pts_allow_7_13 INT,
    pts_allow_14_20 INT,
    pts_allow_21_27 INT,
    pts_allow_28_34 INT,
    pts_allow_35_plus INT,
    xpr INT,
    points DOUBLE PRECISION,
    noppr_points DOUBLE PRECISION,
    PRIMARY KEY (season, week, manager_guid, player_id),
    CONSTRAINT fk_detailed_roster_guid FOREIGN KEY (manager_guid)
        REFERENCES manager_info.managers(manager_guid)
        ON DELETE CASCADE
    CONSTRAINT fk_detailed_roster_teamkey FOREIGN KEY (team_key)
        REFERENCES manager_info.manager_seasons(team_key)
        ON DELETE CASCADE;
);

-- Matchups table
CREATE TABLE IF NOT EXISTS manager_info.matchups (
    week INT NOT NULL,
    week_start DATE,
    week_end DATE,
    is_playoff INT,
    matchup_id INT,
    team_id INT,
    team_name VARCHAR(100),
    team_key VARCHAR(50),
    manager_id INT,
    manager_nickname VARCHAR(50),
    manager_guid VARCHAR(50) NOT NULL,
    points DOUBLE PRECISION,
    projected_points DOUBLE PRECISION,
    winner VARCHAR(10),
    recap_url VARCHAR(255),
    season INT NOT NULL,
    game_quality VARCHAR(10),
    PRIMARY KEY (week, season, manager_guid),
    CONSTRAINT fk_matchups_guid FOREIGN KEY (manager_guid)
        REFERENCES manager_info.managers(manager_guid)
        ON DELETE CASCADE
);

-- Roster Reference table
CREATE TABLE IF NOT EXISTS player_info.roster_reference (
    season INT NOT NULL,
    week INT NOT NULL,
    team VARCHAR(10),
    opponent_team VARCHAR(10),
    player_name VARCHAR(50) NOT NULL,
    position VARCHAR(10),
    PRIMARY KEY (season, week, player_name)
);

-- Trades table
CREATE TABLE IF NOT EXISTS transactions.trades (
    season INT,
    league_id VARCHAR(50) NOT NULL,
    trade_id INT NOT NULL,
    timestamp BIGINT,
    status VARCHAR(50),
    from_team VARCHAR(100),
    from_team_key VARCHAR(100),
    to_team VARCHAR(100),
    to_team_key VARCHAR(100),
    player VARCHAR(100),
    player_id INT NOT NULL,
    pos VARCHAR(10),
    team_abbr VARCHAR(10),
    PRIMARY KEY (league_id, trade_id, player_id),
    CONSTRAINT fk_trades_from_team_key FOREIGN KEY (from_team_key)
        REFERENCES manager_info.manager_seasons(team_key)
        ON DELETE CASCADE,
    CONSTRAINT fk_trades_to_team_key FOREIGN KEY (to_team_key)
        REFERENCES manager_info.manager_seasons(team_key)
        ON DELETE CASCADE
);

-- Waivers table
CREATE TABLE IF NOT EXISTS transactions.waivers (
    season INT,
    league_id VARCHAR(50) NOT NULL,
    trade_id VARCHAR(50) NOT NULL,
    timestamp TIMESTAMP WITHOUT TIME ZONE,
    status VARCHAR(50),
    type VARCHAR(50),
    team VARCHAR(100),
    team_key VARCHAR(100),
    player VARCHAR(100),
    player_id INT NOT NULL,
    pos VARCHAR(10),
    team_abbr VARCHAR(10),
    PRIMARY KEY (league_id, trade_id, player_id),
    CONSTRAINT fk_waivers_team_key FOREIGN KEY (team_key)
        REFERENCES manager_info.manager_seasons(team_key)
        ON DELETE CASCADE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_manager_detailed ON player_info.detailed_roster (manager_guid);
/*
    This index will allow queries to quickly search for a managers team. This is a common query since it is an easy way to see how
    a manager performs historically. This table also stores every single roster in every week, so this table will quickly become large 
    in a few years time, so helpful to be able to quickly find the manager.
*/
CREATE INDEX IF NOT EXISTS idx_position_type_detailed ON player_info.detailed_roster (position_type);
/*
    Position type will be a common column used to filter in queries. There are three types of players that have their own scoring system,
    offense, defense, and kicker. It will often be the case that we only want to look at one of these at a time, and again this table will 
    become very large over the years, so this should speed up queries a bunch.
*/
CREATE INDEX IF NOT EXISTS idx_season_detailed ON player_info.detailed_roster (season);
/*
    Another common filtering column will be season, since we may only want to see the last few years or just the current year. This will
    help get to a much smaller amount of records when querying.
*/
CREATE INDEX IF NOT EXISTS idx_season ON player_info.roster_reference (season);
/*
    This is a large table (every player that has ever played in the NFL for each season) and this is just one of the most common 
    fields to filter on. Each season this table will continue to get larger and larger as well, so being able to quickly pull the
    current season data will speed up practical queries considerably.
*/
CREATE INDEX IF NOT EXISTS idx_position ON player_info.roster_reference (position);
/*
    Again, this is a large table and position is the next most common field to filter on.. Thinking about fantasy football, we 
    often want to know which player to put in for a position in a given week, so of course we would want to filter by position.
*/

-- Other additions
ALTER TABLE player_info.detailed_roster
ADD COLUMN NoPPR_Points float
;

UPDATE player_info.detailed_roster
SET NoPPR_Points = Points - Rec
;

COMMIT;