
##' create sqlite file from an obo file
##'
##'
##' @title create_sqlite
##' @param obofile ontology store in an obo file
##' @param dbfile filename of the output sqlite file
##' @param name name of the ontology
##' @param date release date of the ontology
##' @param url reference url of the ontology
##' @param ont2gene ontology ID to gene ID mapping (optional)
##' @return NULL
##' @importFrom RSQLite dbDriver
##' @importFrom DBI dbConnect
##' @importFrom DBI dbDisconnect
##' @importFrom stats setNames
##' @export
##' @author Guangchuang Yu \url{https://yulab-smu.top}
create_sqlite <- function(
    obofile, 
    dbfile, 
    name="", 
    date="", 
    url="", 
    ont2gene = NULL) {

    drv <- dbDriver("SQLite")
    db <- dbConnect(drv, dbname=dbfile)

    obo <- read.obo(obofile)

    write_db_table_(db, "term", obo$info[, c(1,2)])
    write_db_table_(db, "alias", obo$alias)
    write_db_table_(db, "synonym", obo$synonym)

    parent <- obo$rel
    write_db_table_(db, "parent", parent)
    
    children <- setNames(rev_rel(parent), c("id", "children"))
    write_db_table_(db, "children", children)

    ancestor <- parent2ancestor(parent)
    write_db_table_(db, "ancestor", ancestor)

    offspring <- setNames(rev_rel(ancestor), c("id", "offspring"))
    write_db_table_(db, "offspring", offspring)

    if (!is.null(ont2gene)) {
        write_db_table_(db, "ont2gene", ont2gene)

        gene2allont <- build_gene2allont(ont2gene, ancestor)
        write_db_table_(db, "gene2allont", gene2allont)
    }

    metadata <- data.frame(
        name = c("DBSCHEMA", "DBSCHEMAVERSION", "SOURCENAME",
            "SOURCURL", "SOURCEDATE", "Db type"),
        value = c("ONTOLOGY", "1.0", name,
            url, date, "OntDb")
    )

    write_db_table_(db, "metadata", metadata)

    map.counts <- data.frame(
        map_name = c("TERM", "CHILDREN",
            "PARENTS", "ANCESTOR", "OFFSPRING"),
        count = c(nrow(obo$info), nrow(children), 
            nrow(parent), nrow(ancestor), nrow(offspring))
        )

    write_db_table_(db, "map_counts", map.counts)

    dbDisconnect(db)
    invisible(NULL)
}

##' @importFrom utils stack
parent2ancestor <- function(parent) {
    # parent with two columns, id and parent
    ancestor_list <- split(parent$parent, parent$id)
    getAncestor <- function(id, parent) {
        ans_temp <- which(parent[,1] %in% ancestor_list[[id]])
        ids <- parent[ans_temp, 2]
        content <- c(ancestor_list[[id]], ids)
        while(!all(is.na(ids))) {
            ans_temp <- which(parent[, 1] %in% ids)
            ids <- parent[ans_temp, 2]
            content <- c(content, ids)
        }
        content[!is.na(content)]
    }

    for (id in names(ancestor_list)) {
        ancestor_list[[id]] <- getAncestor(id, parent)
    }
    ancestor <- stack(ancestor_list)[, c(2, 1)]
    ancestor[, 1] <- as.character(ancestor[, 1])
    ancestor <- unique(ancestor)
    colnames(ancestor) <- c("id", "ancestor")
    return(ancestor)
}

##' @importFrom DBI dbWriteTable
write_db_table_ <- function(conn, name, value) {
    dbWriteTable(conn = conn, name, value, row.names=FALSE, overwrite = TRUE)
}

rev_rel <- function(rel) {
    x <- rel[, c(2,1)]
    x[order(x[,1]), ]
}


build_gene2allont <- function(ont2gene, ancestor) {
    eg2ont <- split(as.character(ont2gene[,1]), as.character(ont2gene[,2]))
    # anc <- GOSemSim:::getAncestors(ontology)
    anc <- split(ancestor[,2], ancestor[,1])
    eg2allont <- lapply(eg2ont,
                       function(i) {
                           ans <- unlist(anc[i])
                           ans <- ans[ !is.na(ans) ]
                           ans <- c(i, ans)
                           ans <- unique(ans)
                           return(ans)
                       }) 

    res <- stack(eg2allont)
    res <- res[, c("ind", "values")] |>
        setNames(c("gene", "id"))
    
    return(res)
}

