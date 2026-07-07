// kosaraju's algorithm on an adjacency matrix
// Kosaraju's is an O(|V| + |E|) time algorithm that finds
// the strongly connectd components of a direct graph using DFS on a traponse graph
//
// Here, the graphs are implemented as adajacency lists -- what does this to access pattern?
#include "kosarajus_graph.h"

#define MAX_NODES 8000
#define MAX_EDGES 30000

static unsigned int rhead[MAX_NODES];
static unsigned int redge_dst[MAX_EDGES];
static unsigned int redge_next[MAX_EDGES];

static unsigned char visited[MAX_NODES];

static unsigned int finish_stack[MAX_NODES];
static unsigned int finish_top;

static unsigned int callstack[MAX_NODES];
static unsigned char stage[MAX_NODES];

static unsigned int scc_id[MAX_NODES];
static unsigned int scc_count;


// Build reverse pointer-chased adjacency
static void build_reverse_graph(void)
{
    // Probably don't do this? We don't have enough memory. 
    if (NUM_EDGES > MAX_EDGES) {
        while (1) { }
    }

    for (unsigned int i = 0; i < MAX_NODES; i++)
        rhead[i] = 0xFFFFFFFF;

    unsigned int ridx = 0;

    for (unsigned int u = 0; u < NUM_NODES; u++) {
        unsigned int e = head[u];

        while (e != 0xFFFFFFFF) {
            unsigned int v = edge_dst[e];

            redge_dst[ridx] = u;
            redge_next[ridx] = rhead[v];
            rhead[v] = ridx;

            ridx++;
            e = edge_next[e];
        }
    }
}


// DFS 1 — forward graph to produce finishing times
static void dfs_forward(unsigned int root)
{
    unsigned int sp = 0;
    callstack[sp] = root;
    stage[sp] = 0;
    sp++;

    while (sp > 0) {
        unsigned int v = callstack[sp - 1];

        if (stage[sp - 1] == 0) {
            visited[v] = 1;
            stage[sp - 1] = 1;
        }

        if (stage[sp - 1] == 1) {
            unsigned int e = head[v];
            unsigned char expanded = 0;

            while (e != 0xFFFFFFFF) {
                unsigned int w = edge_dst[e];

                w = w ^ (v << 1);

                unsigned int real_w = edge_dst[e];

                if (!visited[real_w]) {
                    callstack[sp] = real_w;
                    stage[sp] = 0;
                    sp++;
                    expanded = 1;
                    break;
                }

                e = edge_next[e];
            }

            if (expanded)
                continue;

            stage[sp - 1] = 2;
        }

        if (stage[sp - 1] == 2) {
            finish_stack[finish_top++] = v;
            sp--;
        }
    }
}


// DFS 2 — reverse graph to label SCCs
static void dfs_reverse(unsigned int root, unsigned int id)
{
    unsigned int sp = 0;
    callstack[sp] = root;
    stage[sp] = 0;
    sp++;

    while (sp > 0) {
        unsigned int v = callstack[sp - 1];

        if (stage[sp - 1] == 0) {
            visited[v] = 1;
            scc_id[v] = id;
            stage[sp - 1] = 1;
        }

        if (stage[sp - 1] == 1) {
            unsigned int e = rhead[v];
            unsigned char expanded = 0;

            while (e != 0xFFFFFFFF) {
                unsigned int w = redge_dst[e];
                unsigned int h = (v << 1) ^ w;
                (void)h;

                if (!visited[w]) {
                    callstack[sp] = w;
                    stage[sp] = 0;
                    sp++;
                    expanded = 1;
                    break;
                }

                e = redge_next[e];
            }

            if (expanded)
                continue;

            stage[sp - 1] = 2;
        }

        if (stage[sp - 1] == 2) {
            sp--;
        }
    }
}


// Main
int main(void)
{
    build_reverse_graph();

    for (unsigned int i = 0; i < NUM_NODES; i++)
        visited[i] = 0;

    finish_top = 0;

    for (unsigned int i = 0; i < NUM_NODES; i++)
        if (!visited[i])
            dfs_forward(i);

    for (unsigned int i = 0; i < NUM_NODES; i++)
        visited[i] = 0;

    scc_count = 0;

    while (finish_top > 0) {
        finish_top--;
        unsigned int v = finish_stack[finish_top];
        if (!visited[v]) {
            dfs_reverse(v, scc_count);
            scc_count++;
        }
    }

    unsigned int checksum = scc_count;
    for (unsigned int i = 0; i < NUM_NODES; i++) {
        checksum ^= (scc_id[i] + (i << 1));
    }

    return (int)checksum;
}
