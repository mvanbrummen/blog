+++
date = "2016-11-07T19:24:47+10:00"
title = "Building a Singly Linked List in Go"
tags = ["go","data structures","linked list"
]
categories = [
]
featureimage = ""
menu = ""
draft = true

+++

A linked list is a common data structure composed of a linear sequence of data entities called nodes. In a basic example, these nodes contain a piece of data and a reference, through the means of a pointer, to the next node in the sequence.

## Implementation
We will start our implementation by defining SinglyLinkedList and Node structs.
SinglyLinkedList will contain a pointer to a Node called head which will serve as the entry point to the linked sequence.
```go
type SinglyLinkedList struct {
	head *Node
}
```
Node will contain an arbitrary data value of interface{} type and a pointer to the next Node in the list.

```go
type Node struct {
	value interface{}
	next  *Node
}
```
The LinkedList interface will define the basic operations that we will want to implement.
```go
type LinkedList interface {
	InsertBeginning(value interface{})
	InsertAfter(after, value interface{})
	RemoveBeginning()
	RemoveAfter(after interface{})
	Display()
	Search(value interface{}) interface{}
}
```
To insert a node at the beginning of the linked list we will create a pointer to a node and set the value. If head is nil, the list is empty and we can assign the new node to head. If not, we will set the next reference in the new node to head and then replace head with the new node.
```go
func (ll *SinglyLinkedList) InsertBeginning(value interface{}) {
	node := &Node{value: value}
	if ll.head == nil {
		ll.head = node
	} else {
		node.next = ll.head
		ll.head = node
	}
}
```
Inserting after a node requires traversing the list to find the node that matches the search value. Once found, we want to create a new node to place between this current node and the following node.
```go
func (ll *SinglyLinkedList) InsertAfter(after, value interface{}) {
	new := &Node{value: value}
	curr := ll.head
	for curr.value != after {
		curr = curr.next
	}
	new.next = curr.next
	curr.next = new
}
```

If we want to remove the first node, we will simply check if head is not nil then set head to the next reference of head to remove it from the sequence.
```go
func (ll *SinglyLinkedList) RemoveBeginning() {
	if ll.head != nil {
		ll.head = ll.head.next
	}
}
```
To remove after a certain node value we must traverse the list and find the matching node. If the next pointer is nil, then the node is already at the end of the list and nothing needs to change. Otherwise the next pointer is set to the node after the current one, removing it from the sequence.
```go
func (ll *SinglyLinkedList) RemoveAfter(after interface{}) {
	for curr := ll.head; curr != nil; curr = curr.next {
		if curr.value == after {
			if curr.next != nil {
				curr.next = curr.next.next
				return
			}
		}
	}
}
```

The Display method will use a loop to "walk" over the linked list nodes, printing each node along the way, stopping only when the next reference is nil.
```go
func (ll *SinglyLinkedList) Display() {
	for curr := ll.head; curr != nil; curr = curr.next {
		fmt.Printf("%+v\n", curr)
	}
}
```

Similar to the Display method, Search will traverse the linked list, returning a node that matches the search parameter.
```go
func (ll *SinglyLinkedList) Search(value interface{}) interface{} {
	for curr := ll.head; curr != nil; curr = curr.next {
		if curr.value == value {
			return curr
		}
	}
	return nil
}
```


## Putting it all together

```go
package main

import "fmt"

type SinglyLinkedList struct {
	head *Node
}

type Node struct {
	value interface{}
	next  *Node
}

type LinkedList interface {
	Display()
	Search(value interface{}) interface{}
	InsertBeginning(value interface{})
	InsertAfter(after, value interface{})
	RemoveBeginning()
	RemoveAfter(after interface{})
}

func (ll *SinglyLinkedList) InsertBeginning(value interface{}) {
	node := &Node{value: value}
	if ll.head == nil {
		ll.head = node
	} else {
		node.next = ll.head
		ll.head = node
	}
}

func (ll *SinglyLinkedList) InsertAfter(after, value interface{}) {
	new := &Node{value: value}
	curr := ll.head
	for curr.value != after {
		curr = curr.next
	}
	new.next = curr.next
	curr.next = new
}

func (ll *SinglyLinkedList) RemoveBeginning() {
	if ll.head != nil {
		ll.head = ll.head.next
	}
}

func (ll *SinglyLinkedList) RemoveAfter(after interface{}) {
	for curr := ll.head; curr != nil; curr = curr.next {
		if curr.value == after {
			if curr.next != nil {
				curr.next = curr.next.next
				return
			}
		}
	}
}

func (ll *SinglyLinkedList) Display() {
	for curr := ll.head; curr != nil; curr = curr.next {
		fmt.Printf("%+v\n", curr)
	}
}

func (ll *SinglyLinkedList) Search(value interface{}) interface{} {
	for curr := ll.head; curr != nil; curr = curr.next {
		if curr.value == value {
			return curr
		}
	}
	return nil
}
```

```go
package main

import "fmt"

func main() {
	ll := new(SinglyLinkedList)
	ll.InsertBeginning("Harry Potter")
	ll.InsertBeginning("Hermione Granger")
	ll.InsertBeginning("Ron Weasley")
	ll.Display()
	fmt.Println()

	ll.InsertAfter("Harry Potter", "Rubeus Hagrid")
	ll.Display()
	fmt.Println()

	ll.RemoveBeginning()
	ll.RemoveAfter("Harry Potter")
	ll.Display()
	fmt.Println()

	result := ll.Search("Hermione Granger")
	node, _ := result.(*Node)
	fmt.Printf("%s had lots of bushy brown hair, and rather large front teeth.\n", node.value)
}
```

```bash
$ go run *.go
&{value:Ron Weasley next:0xc42000e340}
&{value:Hermione Granger next:0xc42000e320}
&{value:Harry Potter next:<nil>}

&{value:Ron Weasley next:0xc42000e340}
&{value:Hermione Granger next:0xc42000e320}
&{value:Harry Potter next:0xc42000e400}
&{value:Rubeus Hagrid next:<nil>}

&{value:Hermione Granger next:0xc42000e320}
&{value:Harry Potter next:<nil>}

Hermione Granger had lots of bushy brown hair, and rather large front teeth.
```
