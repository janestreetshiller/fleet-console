
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Bright,
    Dark,
    Dither,
}

pub const COLUMNS: usize = 6;
pub const ROWS: usize = 5;

use Tone::{Bright as B, Dark as D, Dither as X};

pub const GRID: [[Option<Tone>; COLUMNS]; ROWS] = [
    [Some(B), Some(B), Some(X), Some(X), Some(D), Some(D)],
    [Some(B), None, Some(D), None, None, Some(D)],
    [Some(B), Some(B), Some(X), None, None, None],
    [Some(B), None, Some(D), None, None, Some(D)],
    [Some(B), None, Some(D), Some(D), Some(D), Some(D)],
];

pub fn cells() -> impl Iterator<Item = (usize, usize, Tone)> {
    GRID.iter().enumerate().flat_map(|(row, line)| {
        line.iter()
            .enumerate()
            .filter_map(move |(column, tone)| tone.map(|t| (row, column, t)))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grid_matches_the_design_asset() {
        let all: Vec<_> = cells().collect();
        assert_eq!(all.len(), 20);
        assert_eq!(all.iter().filter(|c| c.2 == Tone::Bright).count(), 7);
        assert_eq!(all.iter().filter(|c| c.2 == Tone::Dark).count(), 10);
        assert_eq!(all.iter().filter(|c| c.2 == Tone::Dither).count(), 3);
        assert!((0..ROWS).all(|r| GRID[r][0] == Some(Tone::Bright)));
    }
}
