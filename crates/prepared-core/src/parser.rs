use std::collections::HashSet;
use std::fmt;

pub fn parse_queries(src: &str) -> Result<Vec<ParsedQuery>, ParseError>;

pub enum Quantifier {
    One,
    Opt,
    Many,
    Exec,
}

impl Quantifier {
    fn from_tag() {
        
    }
}

pub struct ParsedQuery {
    pub name: String,
    pub sql_named: String,
    pub sql_indexed: String,
    pub param_order: Vec<String>,
    pub nullable_cols: Vec<String>,
    pub row_struct_name: Option<String>,
    pub quantifier: Quantifier,
}