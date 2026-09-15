from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, OuterRef, Q, Subquery
from django.http import Http404
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions, serializers, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.notifications.models import Notification
from apps.notifications.services import NotificationService
from apps.students.models import Student

from .models import Conversation, Message
from .rules import can_send, can_start, contacts_for

User = get_user_model()

MAX_BODY = 2000


def _name(user):
    return f'{user.first_name} {user.last_name}'.strip() or user.username


def _context(viewer, person):
    """One line that tells the viewer who this person is to them."""
    if person.role == 'ADMIN':
        return 'School office'
    if person.role == 'TEACHER':
        homerooms = [f'{c.name} - {c.section}' for c in person.homeroom_classes.all()]
        return f"Class teacher, {', '.join(homerooms)}" if homerooms else 'Teacher'
    children = Student.objects.filter(parents=person, is_active=True)
    if viewer.role == 'TEACHER':
        children = children.filter(class_enrolled__teachers=viewer)
    names = [f'{c.first_name} ({c.class_enrolled.name} - {c.class_enrolled.section})' if c.class_enrolled else c.first_name
             for c in children.select_related('class_enrolled')[:3]]
    return f"Parent of {', '.join(names)}" if names else 'Parent'


class BodySerializer(serializers.Serializer):
    body = serializers.CharField(max_length=MAX_BODY, trim_whitespace=True, allow_blank=False)


class StartSerializer(BodySerializer):
    recipient_id = serializers.IntegerField()


def _person(viewer, person):
    return {'id': person.id, 'full_name': _name(person), 'role': person.role, 'context': _context(viewer, person)}


def _message_row(message, viewer):
    return {
        'id': message.id,
        'body': message.body,
        'sender_id': message.sender_id,
        'is_mine': message.sender_id == viewer.id,
        'created_at': message.created_at,
        'read_at': message.read_at,
    }


def _post_message(conversation, sender, body):
    """Saves a message and tells the other person, without spamming them."""
    recipient = conversation.other_participant(sender)
    with transaction.atomic():
        message = Message.objects.create(conversation=conversation, sender=sender, body=body)
        Conversation.objects.filter(pk=conversation.pk).update(last_message_at=message.created_at)

        # One unread alert per conversation is enough; ten messages in a row
        # must not ring the phone ten times.
        already_alerted = Notification.objects.filter(
            recipient=recipient, conversation=conversation, is_read=False,
        ).exists()
        if not already_alerted and recipient.is_active:
            snippet = body if len(body) <= 120 else body[:117] + '...'
            notification = Notification.objects.create(
                recipient=recipient,
                notification_type=Notification.NotificationType.MESSAGE,
                title=f'Message from {_name(sender)}',
                message=snippet,
                conversation=conversation,
            )
            NotificationService._push([notification])
    return message


class ConversationListView(APIView):
    """
    GET  /api/v1/messages/conversations/   my conversations, newest first
    POST /api/v1/messages/conversations/   {recipient_id, body} start (or continue) one
    """

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'messages'

    def get_throttles(self):
        # Reading is free; only sending is rate limited.
        return super().get_throttles() if self.request.method == 'POST' else []

    def get(self, request):
        user = request.user
        last = Message.objects.filter(conversation=OuterRef('pk')).order_by('-created_at', '-id')
        conversations = (
            Conversation.objects.filter(Q(user_low=user) | Q(user_high=user))
            .select_related('user_low', 'user_high')
            .annotate(
                unread=Count('messages', filter=Q(messages__read_at__isnull=True) & ~Q(messages__sender=user)),
                last_body=Subquery(last.values('body')[:1]),
                last_sender=Subquery(last.values('sender_id')[:1]),
            )
            .order_by('-last_message_at')
        )
        paginator = PageNumberPagination()
        page = paginator.paginate_queryset(conversations, request, view=self)
        return paginator.get_paginated_response([
            {
                'id': c.id,
                'other': _person(user, c.other_participant(user)),
                'last_message': (c.last_body or '')[:140],
                'last_message_is_mine': c.last_sender == user.id,
                'last_message_at': c.last_message_at,
                'unread_count': c.unread,
                'can_reply': can_send(user, c),
            }
            for c in page
        ])

    def post(self, request):
        data = StartSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        user = request.user
        recipient = User.objects.filter(pk=data.validated_data['recipient_id']).first()
        if recipient is None or not can_start(user, recipient):
            # One answer for "no such person" and "not allowed", so ids cannot
            # be probed to learn who exists.
            raise PermissionDenied('You cannot message this person.')

        low, high = sorted([user, recipient], key=lambda person: person.pk)
        conversation, _ = Conversation.objects.get_or_create(
            user_low=low, user_high=high, defaults={'school_id': user.school_id},
        )
        message = _post_message(conversation, user, data.validated_data['body'])
        return Response({
            'id': conversation.id,
            'other': _person(user, recipient),
            'message': _message_row(message, user),
        }, status=status.HTTP_201_CREATED)


def _conversation_for(user, pk):
    conversation = get_object_or_404(
        Conversation.objects.select_related('user_low', 'user_high'), pk=pk,
    )
    if user.pk not in conversation.participant_ids():
        # Not a participant: as far as this user knows, it does not exist.
        raise Http404('Conversation not found.')
    return conversation


class ConversationDetailView(APIView):
    """
    GET /api/v1/messages/conversations/{id}/?before=<message id>
    The latest 50 messages (older with ?before=). Marks the other person's
    messages as read.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        user = request.user
        conversation = _conversation_for(user, pk)

        messages = conversation.messages.order_by('-created_at', '-id')
        before = request.query_params.get('before')
        if before:
            messages = messages.filter(id__lt=before)
        page = list(messages[:50])

        now = timezone.now()
        conversation.messages.filter(read_at__isnull=True).exclude(sender=user).update(read_at=now)
        Notification.objects.filter(recipient=user, conversation=conversation, is_read=False).update(is_read=True)

        return Response({
            'id': conversation.id,
            'other': _person(user, conversation.other_participant(user)),
            'can_reply': can_send(user, conversation),
            'has_older': messages.filter(id__lt=page[-1].id).exists() if page else False,
            'messages': [_message_row(m, user) for m in reversed(page)],
        })


class MessageCreateView(APIView):
    """POST /api/v1/messages/conversations/{id}/messages/  {body}"""

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'messages'

    def post(self, request, pk):
        user = request.user
        conversation = _conversation_for(user, pk)
        if not can_send(user, conversation):
            raise PermissionDenied('You can no longer message this person.')
        data = BodySerializer(data=request.data)
        data.is_valid(raise_exception=True)
        message = _post_message(conversation, user, data.validated_data['body'])
        return Response(_message_row(message, user), status=status.HTTP_201_CREATED)


class ContactsView(APIView):
    """GET /api/v1/messages/contacts/?search=   people I may start a conversation with"""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        people = contacts_for(user)
        search = (request.query_params.get('search') or '').strip()
        if search:
            people = people.filter(
                Q(first_name__icontains=search) | Q(last_name__icontains=search)
                | Q(phone_number__icontains=search) | Q(children__first_name__icontains=search)
            ).distinct()
        people = people.prefetch_related('homeroom_classes').order_by('role', 'first_name', 'last_name')[:50]
        return Response([_person(user, person) for person in people])


class UnreadCountView(APIView):
    """GET /api/v1/messages/unread-count/"""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        count = Message.objects.filter(
            Q(conversation__user_low=user) | Q(conversation__user_high=user),
            read_at__isnull=True,
        ).exclude(sender=user).count()
        return Response({'unread_count': count})
