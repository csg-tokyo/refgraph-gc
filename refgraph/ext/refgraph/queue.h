#ifndef QUEUE_H
#define QUEUE_H 1

#define QUEUE_SIZE (1024 * 16)

typedef struct queue {
    size_t head, tail;
    size_t values_length;
    VALUE* values;
} queue_t;

void Init_refgraph_queue(VALUE mRefgraph);

static inline queue_t* init_queue(queue_t* q)
{
    q->head = q->tail = 0;
    q->values_length = QUEUE_SIZE;
    q->values = (VALUE*)malloc(sizeof(VALUE) * QUEUE_SIZE);
    return q;
}

static inline queue_t* alloc_queue()
{
    queue_t* q = (queue_t*)malloc(sizeof(queue_t));
    return init_queue(q);
}

static inline void destruct_queue(queue_t* q)
{
    free(q->values);
    q->values = NULL;
}

static inline void free_queue(queue_t* q)
{
    destruct_queue(q);
    free(q);
}

static inline int empty_queue(queue_t* q)
{
    return q->head == q->tail;
}

static inline VALUE dequeue(queue_t* q)
{
    if (q->head == q->tail)
        return Qnil;     /* returns nil when empty */
    else {
        size_t h = q->head;
        q->head = (h + 1) % q->values_length;
        return q->values[h];
    }
}

static inline void enqueue(queue_t* q, VALUE v)
{
    size_t t = q->tail;
    q->values[t] = v;
    q->tail = (t + 1) % q->values_length;
    if (q->tail == q->head) {
        size_t new_len = q->values_length * 2;
        VALUE* new_values = (VALUE*)malloc(sizeof(VALUE) * new_len);
        size_t new_head = q->head + q->values_length;
        memcpy(&new_values[new_head], &q->values[q->head],
               (q->values_length - q->head) * sizeof(VALUE));
        if (q->tail > 0)
            memcpy(&new_values[0], &q->values[0], q->tail * sizeof(VALUE));

        q->head = new_head;
        q->values_length = new_len;
        free(q->values);
        q->values = new_values;
    }
}

#endif /* QUEUE_H */
