import jenkins.model.Jenkins

Jenkins.instance.queue.items.each { item ->
    item.getFuture().cancel(true)
    println("Cancelled job: ${item.task.name}")
}
